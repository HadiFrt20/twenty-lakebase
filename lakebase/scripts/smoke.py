"""Log into Twenty via GraphQL and assert the global search returns hits (prefix, accents, domains)."""
import json, os, sys, time, urllib.request

BASE = os.environ.get("TWENTY_URL", "http://localhost:3000")
# Seeded Admin user; tim@apple.dev is object-restricted and gets PERMISSION_DENIED on search.
EMAIL, PASSWORD = "jane.austen@apple.dev", "tim@apple.dev"
CASES = {"chri": 1, "apple": 1, "linkedin.com": 1, "christ jones": 1}


def gql(query, variables, token=None, path="/metadata"):
    headers = {"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})}
    req = urllib.request.Request(BASE + path, json.dumps({"query": query, "variables": variables}).encode(), headers)
    started = time.perf_counter()
    body = json.load(urllib.request.urlopen(req, timeout=60))
    if "errors" in body:
        sys.exit(f"GraphQL error: {json.dumps(body['errors'])[:800]}")
    return body["data"], (time.perf_counter() - started) * 1000


login, _ = gql("mutation($e:String!,$p:String!,$o:String!){getLoginTokenFromCredentials(email:$e,password:$p,origin:$o){loginToken{token}}}",
               {"e": EMAIL, "p": PASSWORD, "o": BASE})
auth, _ = gql("mutation($t:String!,$o:String!){getAuthTokensFromLoginToken(loginToken:$t,origin:$o){tokens{accessOrWorkspaceAgnosticToken{token}}}}",
              {"t": login["getLoginTokenFromCredentials"]["loginToken"]["token"], "o": BASE})
token = auth["getAuthTokensFromLoginToken"]["tokens"]["accessOrWorkspaceAgnosticToken"]["token"]

failed = False
for term, minimum in CASES.items():
    data, ms = gql("query($s:String!){search(searchInput:$s,limit:8){edges{node{objectNameSingular label}}}}", {"s": term}, token, "/graphql")
    hits = data["search"]["edges"]
    ok = len(hits) >= minimum
    failed |= not ok
    print(f"{'PASS' if ok else 'FAIL'} {term!r:16} {len(hits)} hits {ms:5.0f} ms")
sys.exit(1 if failed else 0)
