#!/usr/bin/python
# -*- coding: utf-8 -*-
# Runs ON the TrueNAS host (Ansible ships it there): every read and write goes
# through `midclt call`, TrueNAS's own client for its middleware API — the same
# API the web UI uses. Nothing here touches the OS directly.

from __future__ import annotations

DOCUMENTATION = r"""
module: truenas_object
short_description: Ensure one TrueNAS middleware object exists with given fields
description:
  - Queries C(<namespace>.query) with I(filters), then creates, updates or
    deletes so the object matches I(data). Only the fields in I(data) are
    compared, so unmanaged fields keep whatever value TrueNAS gives them.
  - Field names are the TrueNAS API's own (v25.10), unchanged.
options:
  namespace:
    description: API namespace, e.g. C(user), C(group), C(pool.dataset), C(sharing.smb).
    type: str
    required: true
  filters:
    description: Query filters that select exactly one object, e.g. C([["name", "=", "media"]]).
    type: list
    elements: raw
    required: true
  data:
    description: Desired fields, as the create/update methods take them.
    type: dict
    default: {}
  secret_data:
    description: Fields sent on create only and never shown in output (passwords).
    type: dict
    default: {}
  create_only:
    description: Keys of I(data) sent on create but never compared or updated.
    type: list
    elements: str
    default: []
  immutable:
    description:
      - Keys of I(data) that must already match on an existing object. A
        mismatch fails instead of updating (UIDs and GIDs own files on disk).
    type: list
    elements: str
    default: []
  refs:
    description:
      - Keys of I(data) holding names to turn into API ids. Each entry has
        C(key), C(namespace), C(many) (a list of references) and C(match):
        either a field name (the reference is a string) or nothing (the
        reference is a dict of field filters).
    type: list
    elements: dict
    default: []
  state:
    type: str
    choices: [present, absent]
    default: present
  allow_delete:
    description: Required for C(state=absent) on C(pool.dataset), which deletes data.
    type: bool
    default: false
  delete_args:
    description: Extra arguments for C(<namespace>.delete), after the id.
    type: list
    elements: raw
    default: []
"""

import json
import subprocess

from ansible.module_utils.basic import AnsibleModule


class MiddlewareError(Exception):
    pass


def midclt(method, *args):
    cmd = ["midclt", "call", method] + [json.dumps(a) for a in args]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise MiddlewareError("%s failed: %s" % (method, (proc.stderr or proc.stdout).strip()))
    out = proc.stdout.strip()
    if not out:
        return None
    try:
        return json.loads(out)
    except ValueError:
        # midclt prints string results raw (system.version → TrueNAS-25.10.7),
        # everything else as JSON.
        return out


def is_property(value):
    # pool.dataset.query returns ZFS properties as {value, rawvalue, parsed, source}.
    return isinstance(value, dict) and "rawvalue" in value and "value" in value


def normalise_list(items):
    # Query results reference other objects as full dicts (a replication's
    # periodic_snapshot_tasks); create/update take their ids.
    return [i["id"] if isinstance(i, dict) and "id" in i else i for i in items]


def field(current, key):
    # 25.10's pool.dataset.query keeps user properties (comments, quota_warning,
    # …) under `user_properties`, while create/update take them at the top level.
    if key in current:
        return current[key]
    return (current.get("user_properties") or {}).get(key)


def same(desired, current):
    if is_property(current):
        if desired == current.get("parsed"):
            return True
        return str(desired).upper() == str(current.get("value")).upper()
    if isinstance(desired, dict) and isinstance(current, dict):
        if "id" in current and set(desired) == {"id"}:
            return desired["id"] == current["id"]
        return all(k in current and same(v, current[k]) for k, v in desired.items())
    if isinstance(current, dict) and "id" in current and not isinstance(desired, dict):
        # e.g. a user's primary `group`: create takes the id, query returns the group.
        return desired == current["id"]
    if isinstance(desired, list) and isinstance(current, list):
        cur = normalise_list(current)
        if all(isinstance(x, (str, int, float, bool)) for x in desired + cur):
            return sorted(desired, key=repr) == sorted(cur, key=repr)
        return len(desired) == len(cur) and all(same(d, c) for d, c in zip(desired, cur))
    return desired == current


def resolve_one(ref, value):
    if isinstance(value, dict):
        filters = [[k, "=", v] for k, v in value.items()]
    else:
        filters = [[ref["match"], "=", value]]
    found = midclt(ref["namespace"] + ".query", filters)
    if len(found) != 1:
        return None
    return found[0]["id"]


def resolve_refs(refs, data):
    """Replace names with ids. Returns the names that do not exist yet."""
    missing = []
    for ref in refs:
        key = ref["key"]
        if key not in data or data[key] is None:
            continue
        if ref.get("many"):
            ids = []
            for v in data[key]:
                rid = resolve_one(ref, v)
                if rid is None:
                    missing.append("%s %s" % (ref["namespace"], v))
                ids.append(rid)
            data[key] = ids
        else:
            rid = resolve_one(ref, data[key])
            if rid is None:
                missing.append("%s %s" % (ref["namespace"], data[key]))
            data[key] = rid
    return missing


def visible(current, keys):
    out = {}
    for k in keys:
        v = field(current, k)
        if is_property(v):
            v = v.get("value")
        elif isinstance(v, list):
            v = normalise_list(v)
        elif isinstance(v, dict) and "id" in v and not k == "options":
            v = v["id"]
        out[k] = v
    return out


def main():
    module = AnsibleModule(
        argument_spec=dict(
            namespace=dict(type="str", required=True),
            filters=dict(type="list", elements="raw", required=True),
            data=dict(type="dict", default={}),
            secret_data=dict(type="dict", default={}, no_log=True),
            create_only=dict(type="list", elements="str", default=[]),
            immutable=dict(type="list", elements="str", default=[]),
            refs=dict(type="list", elements="dict", default=[]),
            state=dict(type="str", choices=["present", "absent"], default="present"),
            allow_delete=dict(type="bool", default=False),
            delete_args=dict(type="list", elements="raw", default=[]),
        ),
        supports_check_mode=True,
    )
    p = module.params
    ns = p["namespace"]
    result = dict(changed=False, namespace=ns, id=None, action="none")

    try:
        found = midclt(ns + ".query", p["filters"])
        if len(found) > 1:
            module.fail_json(msg="%s: filters %s match %d objects; they must select one"
                             % (ns, json.dumps(p["filters"]), len(found)), **result)
        current = found[0] if found else None

        if p["state"] == "absent":
            if current is None:
                module.exit_json(**result)
            if ns == "pool.dataset" and not p["allow_delete"]:
                module.fail_json(msg="refusing to delete dataset %s: deleting a dataset deletes its "
                                     "data; set allow_delete: true if that is really meant"
                                     % current["id"], **result)
            result.update(changed=True, id=current["id"], action="delete")
            if not module.check_mode:
                midclt(ns + ".delete", current["id"], *p["delete_args"])
            module.exit_json(**result)

        data = json.loads(json.dumps(p["data"]))
        missing = resolve_refs(p["refs"], data)
        if missing and not module.check_mode:
            module.fail_json(msg="%s: referenced objects do not exist: %s" % (ns, ", ".join(missing)),
                             **result)

        if current is None:
            after = dict(data)
            for ref in p["refs"]:
                # Not created yet (check mode): show the declared name, not a null id.
                v = after.get(ref["key"])
                if v is None or (isinstance(v, list) and None in v):
                    after[ref["key"]] = p["data"][ref["key"]]
            result.update(changed=True, action="create", diff=dict(before={}, after=after))
            if missing:
                result["warnings"] = ["created after: %s (check mode)" % ", ".join(missing)]
            if not module.check_mode:
                created = midclt(ns + ".create", dict(data, **p["secret_data"]))
                result["id"] = created.get("id") if isinstance(created, dict) else created
            module.exit_json(**result)

        result["id"] = current["id"]
        for key in p["immutable"]:
            if key in data and not same(data[key], field(current, key)):
                module.fail_json(msg="%s %s: %s is %s on the system but %s in the declaration; "
                                     "it is immutable here (it owns files on disk) — fix the "
                                     "declaration, or change it deliberately in the UI"
                                 % (ns, current["id"], key, json.dumps(visible(current, [key])[key]),
                                    json.dumps(data[key])), **result)

        skip = set(p["create_only"]) | set(p["immutable"])
        changed = {k: v for k, v in data.items() if k not in skip and not same(v, field(current, k))}
        if changed:
            result.update(changed=True, action="update",
                          diff=dict(before=visible(current, changed.keys()), after=changed))
            if not module.check_mode:
                midclt(ns + ".update", current["id"], changed)
        module.exit_json(**result)
    except MiddlewareError as exc:
        module.fail_json(msg=str(exc), **result)


if __name__ == "__main__":
    main()
