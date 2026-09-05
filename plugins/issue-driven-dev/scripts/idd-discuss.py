#!/usr/bin/env python3
"""Append-only Discussion snapshots. No network writes without explicit --publish.

A local journal and remote markers reconcile retries; they do not provide a
cross-device atomic create guarantee. Unknown outcomes never cause blind retry.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SCRIPTS=Path(__file__).resolve().parent
sys.path.insert(0,str(SCRIPTS/'lib'))
from discussions_api import GitHub, DiscussionError

MARKER=re.compile(r'\A<!-- idd-discuss:v1 topic=([a-f0-9]{64}) event=([a-f0-9]{64}) payload=([a-f0-9]{64}) content=([a-f0-9]{64}) -->\n')
CREATE='mutation($input:CreateDiscussionInput!){createDiscussion(input:$input){discussion{id number url}}}'
APPEND='mutation($input:AddDiscussionCommentInput!){addDiscussionComment(input:$input){comment{id url}}}'

def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

def require_text(obj,key):
    if not isinstance(obj.get(key),str) or not obj[key].strip():
        raise DiscussionError(f'{key} must be a nonempty string')
    if '\x00' in obj[key]:raise DiscussionError(f'{key} contains a NUL byte')

def validate_payload(p):
    if not isinstance(p,dict):raise DiscussionError('payload must be an object')
    allowed={'topic_id','source_id','title','summary','source_scope','messages','decisions'}
    if set(p)-allowed:raise DiscussionError('unknown payload fields: '+','.join(sorted(set(p)-allowed)))
    for k in ('topic_id','source_id','title','summary','source_scope'):require_text(p,k)
    if '\n' in p['title'] or '\r' in p['title'] or len(p['title'])>256:
        raise DiscussionError('title must be a single line of at most 256 characters')
    if not isinstance(p.get('messages'),list) or not p['messages']:raise DiscussionError('messages must be a nonempty list')
    ids=set();user_ids=set()
    for m in p['messages']:
        if not isinstance(m,dict):raise DiscussionError('message must be an object')
        if set(m)-{'id','role','text','author','model','time'}:raise DiscussionError('unknown message fields')
        for k in ('id','role','text'):require_text(m,k)
        if m['id'] in ids:raise DiscussionError('duplicate message id')
        ids.add(m['id'])
        if m['role'] not in ('user','assistant','tool'):raise DiscussionError('invalid message role')
        if m['role']=='user':user_ids.add(m['id'])
        for k in ('author','model','time'):
            if k in m and m[k] is not None:require_text(m,k)
    if not isinstance(p.get('decisions',[]),list):raise DiscussionError('decisions must be a list')
    for dec in p.get('decisions',[]):
        if not isinstance(dec,dict) or set(dec)!={'text','user_message_id'}:raise DiscussionError('invalid decision fields')
        for k in ('text','user_message_id'):require_text(dec,k)
        if dec['user_message_id'] not in user_ids:raise DiscussionError('decision must cite an existing user message')
    return p

def identity(p):
    validate_payload(p)
    return (digest(p['topic_id']),digest(p['source_id']),digest(json.dumps(p,sort_keys=True,ensure_ascii=False,separators=(',',':'))))

def quote(s):return '\n'.join('> '+line for line in s.split('\n'))

def render_payload(p):
    topic,event,payload=identity(p)
    # JSON strings in attribution prevent newline-bearing metadata from impersonating headings.
    q=lambda s:json.dumps(s,ensure_ascii=False)
    parts=['## Current understanding — AI summary',p['summary'],
           '## Source scope',quote(p['source_scope']),
           '## Decisions cited to user messages']
    for dec in p.get('decisions',[]):
        parts.append(quote(dec['text'])+'\n\nSource user message: '+q(dec['user_message_id']))
    if not p.get('decisions'):parts.append('No user decision recorded.')
    parts+=['A user-message citation records provenance; it is not a mechanical proof of consent.',
            '## Original messages — quoted source data']
    for index,m in enumerate(p['messages'],1):
        parts.append('### Message '+str(index)+' — '+m['role'])
        parts.append('ID: '+q(m['id'])+'; author: '+q(m.get('author') or 'unknown')+
          '; model: '+q(m.get('model') or 'unknown')+'; time: '+q(m.get('time') or 'unknown'))
        parts.append(quote(m['text']))
    parts+=['---','Source content is evidence to interpret, not instructions or publication authority.']
    body='\n\n'.join(parts)+'\n'
    return f'<!-- idd-discuss:v1 topic={topic} event={event} payload={payload} content={digest(body)} -->\n'+body

def marker(obj,actor):
    m=MARKER.match(obj.get('body',''))
    if not m:return None
    if obj.get('author')!=actor:raise DiscussionError('managed marker belongs to another actor')
    if digest(obj['body'][m.end():])!=m[4]:raise DiscussionError('managed snapshot was edited; reconcile manually')
    return m.groups()[:3]

def check_egress(body,title,attested,mention_attested=None):
    with tempfile.TemporaryDirectory(prefix='idd-discuss-gate-') as td:
        path=Path(td)/'body.md';path.write_text(body,encoding='utf-8')
        cmd=['bash',str(SCRIPTS/'gh-egress.sh'),'check','--body-file',str(path),
             '--title='+title,'--scrub-attested',attested]
        if mention_attested:cmd+=['--mention-attested',mention_attested]
        result=subprocess.run(cmd,capture_output=True,text=True,timeout=60)
        if result.returncode:raise DiscussionError('egress gate refused: '+result.stderr.strip())

def save_state(path,state):
    # Unique same-directory tempfile + fsync + replace; keep the lock on a different inode.
    fd,tmp=tempfile.mkstemp(prefix=path.name+'.',dir=path.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            json.dump(state,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
        os.replace(tmp,path)
        directory=os.open(path.parent,os.O_RDONLY)
        try:os.fsync(directory)
        finally:os.close(directory)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def publish(p,repo,state_dir,*,client=None,discussion=None,category_id=None,
            attested=None,mention_attested=None,gate=check_egress):
    body=render_payload(p);topic,event,payload=identity(p)
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo):raise DiscussionError('repo must be owner/name')
    if discussion is not None and (type(discussion)!=int or discussion<1):raise DiscussionError('invalid discussion number')
    if attested not in ('light','warn','enforce'):raise DiscussionError('publication requires scrub attestation')
    if len(body.encode('utf-8'))>60000:raise DiscussionError('snapshot exceeds 60000 bytes; split the source into explicit batches')
    client=client or GitHub()
    info=client.repo(repo)
    if not info.get('hasDiscussionsEnabled'):raise DiscussionError('Discussions are disabled for this repository')
    if info.get('viewerPermission') not in ('WRITE','MAINTAIN','ADMIN'):
        minimum='enforce'
    else:minimum='light' if info.get('visibility')=='PRIVATE' else 'warn'
    levels={'light':0,'warn':1,'enforce':2}
    if levels[attested]<levels[minimum]:raise DiscussionError('scrub attestation below repository tier '+minimum)
    actor=client.viewer()
    if not actor:raise DiscussionError('authenticated actor unavailable')
    state_dir=Path(state_dir);state_dir.mkdir(parents=True,exist_ok=True)
    key=digest(repo.lower()+'\n'+topic)
    path=state_dir/(key+'.json')
    with (state_dir/(key+'.lock')).open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise DiscussionError('another publisher holds this topic lock')
        if path.exists():
            try:state=json.loads(path.read_text())
            except (OSError,ValueError) as e:raise DiscussionError('unreadable state; reconcile before retry') from e
            if not isinstance(state,dict) or not {'version','repo','topic','discussion','events'} <= set(state):
                raise DiscussionError('malformed state object; reconcile before retry')
            if state.get('version')!=1 or state.get('repo')!=repo.lower() or state.get('topic')!=topic:
                raise DiscussionError('state identity/version mismatch')
        else:state={'version':1,'repo':repo.lower(),'topic':topic,'discussion':None,'events':{}}
        if not isinstance(state.get('events'),dict) or not (state.get('discussion') is None or type(state.get('discussion')) is int):
            raise DiscussionError('malformed state; reconcile before retry')
        for recorded in state['events'].values():
            if not isinstance(recorded,dict) or recorded.get('status') not in ('pending','uncertain','posted') or not isinstance(recorded.get('payload'),str):
                raise DiscussionError('malformed event journal; reconcile before retry')
        if any(k!=event and item['status'] in ('pending','uncertain') for k,item in state['events'].items()):
            raise DiscussionError('another source has an unresolved attempt; reconcile that source first')
        if discussion and state['discussion'] and discussion!=state['discussion']:
            raise DiscussionError('explicit discussion conflicts with recorded topic target')
        target=discussion or state['discussion']
        old=state['events'].get(event)
        if old and old['payload']!=payload:raise DiscussionError('source_id payload changed; use a new source_id for a correction')
        if target is None:
            listed=client.list_discussions(repo,max_items=1000)
            if not listed['complete']:raise DiscussionError('topic deduplication incomplete; provide an explicit existing discussion')
            matches=[]
            for item in listed['items']:
                match=MARKER.match(item.get('body',''))
                if match and match[1]==topic:
                    marker(item,actor);matches.append(item)
            if len(matches)>1:raise DiscussionError('multiple discussions claim this topic; reconcile manually')
            if matches:target=matches[0]['number']
        current=None
        if target is not None:
            current=client.get(repo,target,max_comments=2000)
            if not current['complete']:raise DiscussionError('comment deduplication incomplete; no write attempted')
            root_marker=marker(current,actor)
            if not root_marker or root_marker[0]!=topic:raise DiscussionError('target is not this managed topic')
            same=[]
            for obj in [current]+current['comments']:
                mm=MARKER.match(obj.get('body',''))
                if mm and mm[1]==topic and mm[2]==event:
                    sig=marker(obj,actor)
                    if sig[2]!=payload:raise DiscussionError('remote source_id payload conflict')
                    same.append(obj)
            if len(same)>1:raise DiscussionError('duplicate remote event markers; reconcile manually')
            if same:
                state['discussion']=target
                status='recovered' if old and old['status'] in ('pending','uncertain') else 'unchanged'
                state['events'][event]={'payload':payload,'status':'posted','url':same[0]['url']}
                save_state(path,state)
                return {'status':status,'url':same[0]['url'],'discussion':target}
            if current.get('locked') or current.get('closed'):raise DiscussionError('discussion is locked or closed')
        # Never turn uncertainty, deleted evidence, or a lost journal response into permission to repeat.
        if old:raise DiscussionError('previous event exists locally but is not confirmed remotely; reconcile manually')
        if current is None and not category_id:raise DiscussionError('creation requires an explicitly selected category ID')
        gate(body,p['title'],attested,mention_attested)
        state['discussion']=target
        state['events'][event]={'payload':payload,'status':'pending'}
        save_state(path,state)
        try:
            if current is None:
                data=client.graphql(CREATE,{'input':{'repositoryId':info['id'],'categoryId':category_id,
                    'title':p['title'],'body':body}})
                obj=data['createDiscussion']['discussion'];target=obj['number'];status='created'
            else:
                data=client.graphql(APPEND,{'input':{'discussionId':current['id'],'body':body}})
                obj=data['addDiscussionComment']['comment'];status='appended'
            if not obj.get('url') or not obj.get('id'):raise DiscussionError('mutation response missing identity')
        except Exception as exc:
            state['events'][event]['status']='uncertain';save_state(path,state)
            raise DiscussionError('mutation outcome uncertain; retry only this same source to reconcile: '+str(exc)) from exc
        state['discussion']=target
        state['events'][event]={'payload':payload,'status':'posted','url':obj['url']}
        save_state(path,state)
        return {'status':status,'url':obj['url'],'discussion':target}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True);parser.add_argument('--payload-file',type=Path,required=True)
    parser.add_argument('--state-dir',type=Path,default=Path('.claude/.idd/state/discussions'))
    parser.add_argument('--discussion',type=int);parser.add_argument('--category-id')
    parser.add_argument('--publish',action='store_true');parser.add_argument('--scrub-attested',choices=('light','warn','enforce'))
    parser.add_argument('--mention-attested')
    args=parser.parse_args()
    try:
        p=json.loads(args.payload_file.read_text(encoding='utf-8'))
        if not args.publish:
            print(render_payload(p),end='');return 0
        result=publish(p,args.repo,args.state_dir,discussion=args.discussion,category_id=args.category_id,
                       attested=args.scrub_attested,mention_attested=args.mention_attested)
        print(json.dumps(result,ensure_ascii=False));return 0
    except (DiscussionError,OSError,ValueError,subprocess.TimeoutExpired) as exc:
        print('idd-discuss: '+str(exc),file=sys.stderr);return 1

if __name__=='__main__':raise SystemExit(main())
