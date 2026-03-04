import json, os
import valkey

def handler(event, context):
    r = valkey.Valkey(
        host=os.environ["ELASTICACHE_ENDPOINT"],
        port=6379,
        ssl=True,
        ssl_cert_reqs=None,
        decode_responses=True,
    )
    key = event.get("key")
    value = r.get(key)
    ttl = r.ttl(key)
    return {
        "key": key,
        "ttl_seconds": ttl,
        "value": json.loads(value) if value else None,
    }