import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(SCRIPTS/'lib'))
spec=importlib.util.spec_from_file_location('publisher',SCRIPTS/'idd-discuss.py')
pub=importlib.util.module_from_spec(spec);spec.loader.exec_module(pub)

class FakeGitHub:
    def __init__(self):self.items=[];self.writes=[];self.fail=False;self.lose_response=False
    def repo(self,r):return {'id':'R1','hasDiscussionsEnabled':True,'visibility':'PUBLIC','viewerPermission':'ADMIN'}
    def viewer(self):return 'tester'
    def list_discussions(self,r,max_items=1000):return {'items':self.items,'complete':True,'warnings':[]}
    def get(self,r,n,max_comments=2000):return next(x for x in self.items if x['number']==n)
    def graphql(self,q,variables):
        inp=variables['input'];self.writes.append(inp)
        if self.fail:raise pub.DiscussionError('request failed')
        if 'createDiscussion' in q:
            obj={'id':'D1','number':1,'url':'https://github.com/acme/repo/discussions/1','body':inp['body'],
                 'author':'tester','closed':False,'locked':False,'comments':[],'complete':True,'warnings':[]}
            self.items.append(obj);result={'createDiscussion':{'discussion':obj}}
        else:
            obj={'id':f'C{len(self.writes)}','url':'https://github.com/acme/repo/discussions/1#discussioncomment-2',
                 'body':inp['body'],'author':'tester'}
            self.items[0]['comments'].append(obj);result={'addDiscussionComment':{'comment':obj}}
        if self.lose_response:raise pub.DiscussionError('response lost')
        return result

class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.state=Path(self.tmp.name)/'state';self.gh=FakeGitHub()
        self.payload={'topic_id':'topic-1','source_id':'batch-1','title':'A topic','summary':'AI summary',
          'source_scope':'Visible messages 1–2 only','messages':[{'id':'u1','role':'user','text':'Please record this.'},
          {'id':'a1','role':'assistant','text':'A tentative proposal.'}]}
    def run_publish(self,**kwargs):
        return pub.publish(self.payload,'acme/repo',self.state,client=self.gh,category_id='CAT',
            attested='warn',gate=lambda *a,**k:None,**kwargs)
    def test_initial_and_retry(self):
        r=self.run_publish();self.assertEqual(r['status'],'created')
        self.assertEqual(self.run_publish()['status'],'unchanged');self.assertEqual(len(self.gh.writes),1)
    def test_append_preserves_root_and_retries(self):
        self.run_publish();old=self.gh.items[0]['body'];self.payload['source_id']='batch-2'
        self.payload['summary']='Correction to initial proposal.'
        self.assertEqual(self.run_publish()['status'],'appended');self.assertEqual(self.gh.items[0]['body'],old)
        self.assertEqual(self.run_publish()['status'],'unchanged');self.assertEqual(len(self.gh.writes),2)
    def test_changed_source_refused(self):
        self.run_publish();self.payload['summary']='Different'
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_decision_requires_user_source(self):
        self.payload['decisions']=[{'text':'Approved','user_message_id':'a1'}]
        with self.assertRaises(pub.DiscussionError):pub.validate_payload(self.payload)
    def test_unknown_attribution_and_quote(self):
        body=pub.render_payload(self.payload)
        self.assertIn('unknown',body);self.assertIn('> A tentative proposal.',body)
    def test_no_automatic_repeat_after_unknown(self):
        self.gh.fail=True
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.gh.fail=False
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_recover_lost_response(self):
        self.gh.lose_response=True
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.gh.lose_response=False
        self.assertEqual(self.run_publish()['status'],'recovered');self.assertEqual(len(self.gh.writes),1)
    def test_locked_closed_and_disabled(self):
        self.run_publish();self.payload['source_id']='batch-2'
        for field in ['locked','closed']:
            self.gh.items[0][field]=True
            with self.assertRaises(pub.DiscussionError):self.run_publish()
            self.gh.items[0][field]=False
        with patch.object(self.gh,'repo',return_value={'hasDiscussionsEnabled':False}):
            with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_incomplete_dedup_refused(self):
        with patch.object(self.gh,'list_discussions',return_value={'items':[],'complete':False,'warnings':['cap']}):
            with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertFalse(self.gh.writes)
    def test_different_actor_cannot_supply_managed_marker(self):
        self.run_publish();self.payload['source_id']='batch-2';self.gh.items[0]['author']='intruder'
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_conflicting_target(self):
        self.run_publish()
        with self.assertRaises(pub.DiscussionError):self.run_publish(discussion=2)
    def test_unknown_attempt_cannot_be_skipped_with_new_source(self):
        self.gh.fail=True
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.gh.fail=False;self.payload['source_id']='different-batch'
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_manual_snapshot_edit_refused(self):
        self.run_publish();self.gh.items[0]['body']+='Human amendment'
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_payload_missing_messages_is_a_user_error(self):
        self.payload.pop('messages')
        with self.assertRaises(pub.DiscussionError):pub.validate_payload(self.payload)
    def test_real_gate_rejects_body_and_option_shaped_title(self):
        for field,value in [('summary','private /Users/alice/work'),('title','--repo=/Users/alice/work')]:
            p=dict(self.payload);p[field]=value
            with self.assertRaises(pub.DiscussionError):pub.publish(p,'acme/repo',self.state,
                client=self.gh,category_id='CAT',attested='warn')
        self.assertFalse(self.gh.writes)
    def test_real_gate_clean_check_never_dispatches(self):
        import os
        td=Path(self.tmp.name);sentinel=td/'called';gh=td/'gh'
        gh.write_text('#!/bin/sh\nprintf called > "'+str(sentinel)+'"\nexit 99\n');gh.chmod(0o755)
        with patch.dict(os.environ,{'PATH':str(td)+os.pathsep+os.environ['PATH']}):
            pub.check_egress('A complete source snapshot','A title','warn')
        self.assertFalse(sentinel.exists())
    def test_same_title_different_topics_stay_separate(self):
        self.run_publish();p=dict(self.payload);p['topic_id']='different-topic'
        result=pub.publish(p,'acme/repo',self.state,client=self.gh,category_id='CAT',
            attested='warn',gate=lambda *a:None)
        self.assertEqual(result['status'],'created');self.assertEqual(len(self.gh.writes),2)
    def test_busy_lock_does_not_write(self):
        import fcntl
        self.state.mkdir()
        key=pub.digest('acme/repo\n'+pub.digest(self.payload['topic_id']))
        with (self.state/(key+'.lock')).open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertFalse(self.gh.writes)
    def test_append_recovers_after_lost_response(self):
        self.run_publish();self.payload['source_id']='batch-2';self.gh.lose_response=True
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.gh.lose_response=False
        self.assertEqual(self.run_publish()['status'],'recovered');self.assertEqual(len(self.gh.writes),2)
    def test_partial_comments_prevent_write(self):
        self.run_publish();self.payload['source_id']='batch-2';self.gh.items[0]['complete']=False
        with self.assertRaises(pub.DiscussionError):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_unattested_mention_and_missing_scrub_fail(self):
        with self.assertRaises(pub.DiscussionError):pub.check_egress('Hello @octocat','Topic','warn')
        with self.assertRaises(pub.DiscussionError):pub.publish(self.payload,'acme/repo',self.state,
            client=self.gh,category_id='CAT')
        self.assertFalse(self.gh.writes)
    def test_malformed_state_reports_reconcile(self):
        self.state.mkdir()
        key=pub.digest('acme/repo\n'+pub.digest(self.payload['topic_id']))
        path=self.state/(key+'.json')
        for bad in [[],None,{'version':1,'repo':'acme/repo','topic':pub.digest(self.payload['topic_id']),'events':{}}]:
            path.write_text(json.dumps(bad))
            with self.assertRaisesRegex(pub.DiscussionError,'reconcile'):self.run_publish()
        self.assertFalse(self.gh.writes)
    def test_all_line_endings_are_quoted_and_hash_stable(self):
        for sep in ['\n','\r\n','\r']:
            self.payload['messages'][0]['text']='first'+sep+'## source heading'
            self.payload['summary']='summary'+sep+'next line'
            body=pub.render_payload(self.payload)
            self.assertNotIn('\r',body)
            self.assertIn('> first\n> ## source heading',body)
            self.assertIn('Line endings',body)
            obj={'body':body.replace('\r\n','\n'),'author':'tester'}
            self.assertEqual(pub.marker(obj,'tester')[:2],pub.identity(self.payload)[:2])
    def test_snapshot_title_is_in_body_but_display_title_can_change(self):
        self.run_publish()
        self.assertIn('> A topic',self.gh.items[0]['body'])
        self.gh.items[0]['title']='Human renamed display title'
        self.assertEqual(self.run_publish()['status'],'unchanged')
        self.payload['source_id']='next';self.payload['title']='A later snapshot title'
        self.run_publish()
        self.assertIn('> A later snapshot title',self.gh.items[0]['comments'][0]['body'])
        self.assertEqual(self.gh.items[0]['title'],'Human renamed display title')
    def test_malformed_mutation_response_is_uncertain_and_recovers(self):
        import copy
        for key,value in [('number','1'),('number',True),('number',0),('id',[]),('id',' '),('url',{}),('url','')]:
            with self.subTest(key=key,value=value):
                self.gh=FakeGitHub();state=self.state/(key+str(value))
                original=self.gh.graphql
                def corrupt(q,variables):
                    result=copy.deepcopy(original(q,variables))
                    result['createDiscussion']['discussion'][key]=value
                    return result
                self.gh.graphql=corrupt
                with self.assertRaisesRegex(pub.DiscussionError,'uncertain'):
                    pub.publish(self.payload,'acme/repo',state,client=self.gh,category_id='CAT',attested='warn',gate=lambda *a:None)
                self.gh.graphql=original
                result=pub.publish(self.payload,'acme/repo',state,client=self.gh,category_id='CAT',attested='warn',gate=lambda *a:None)
                self.assertEqual(result['status'],'recovered');self.assertEqual(len(self.gh.writes),1)
    def test_malformed_append_identity_is_uncertain(self):
        import copy
        self.run_publish();self.payload['source_id']='next';original=self.gh.graphql
        def corrupt(q,variables):
            result=copy.deepcopy(original(q,variables))
            result['addDiscussionComment']['comment']['id']=True
            return result
        self.gh.graphql=corrupt
        with self.assertRaisesRegex(pub.DiscussionError,'uncertain'):self.run_publish()
        self.gh.graphql=original
        self.assertEqual(self.run_publish()['status'],'recovered')
        self.assertEqual(len(self.gh.writes),2)
    def test_zero_or_negative_state_discussion_is_refused(self):
        self.run_publish();path=next(self.state.glob('*.json'));state=json.loads(path.read_text())
        for value in [0,-1,True,'1']:
            state['discussion']=value;path.write_text(json.dumps(state))
            with self.assertRaisesRegex(pub.DiscussionError,'reconcile'):self.run_publish()
        self.assertEqual(len(self.gh.writes),1)
    def test_gate_stops_before_mutation(self):
        def stop(*a,**k):raise pub.DiscussionError('gate refused')
        with self.assertRaises(pub.DiscussionError):pub.publish(self.payload,'acme/repo',self.state,
            client=self.gh,category_id='CAT',attested='warn',gate=stop)
        self.assertFalse(self.gh.writes)

if __name__=='__main__':unittest.main()
