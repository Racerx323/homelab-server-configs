"""Nautobot 3.2.3 fixture operations, invoked only by a reviewed workload stage.

No module-level Django setup, registration, deletion, or network operations.
"""
import hashlib
import ipaddress
import json
import re


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def require(value, code):
    if not value:
        raise ValueError(code)


def plan(dataset):
    require(set(dataset) == {'schema_version', 'namespace', 'locations', 'devices', 'ip_assignments'}
            and dataset['schema_version'] == 1 and dataset['namespace'] == 'pilot-synthetic', 'fixture_shape')
    require(0 < len(dataset['locations']) <= len(dataset['devices']) <= 64000
            and len(dataset['ip_assignments']) <= len(dataset['devices']), 'fixture_counts')
    nodes, keys = [], set()

    def add(key, model, lookup, fields=None, content_types=None):
        require(key not in keys, 'duplicate_key')
        keys.add(key)
        nodes.append(dict(key=key, model=model, lookup=lookup, fields=fields or {}, content_types=content_types))

    def ref(key):
        return {'ref': key}

    name = dataset['namespace']
    add('namespace', 'ipam.namespace', {'name': name}, {'tenant': None, 'location': None})
    add('status', 'extras.status', {'name': name}, {'color': '9e9e9e'},
        ['dcim.location', 'dcim.device', 'dcim.interface', 'ipam.prefix', 'ipam.ipaddress'])
    add('role', 'extras.role', {'name': name}, {'color': '9e9e9e'}, ['dcim.device'])
    add('location_type', 'dcim.locationtype', {'name': name}, fields={'parent': None, 'nestable': False}, content_types=['dcim.device'])
    add('manufacturer', 'dcim.manufacturer', {'name': name})
    add('device_type', 'dcim.devicetype', {'manufacturer': ref('manufacturer'), 'model': name},
        {'u_height': 0, 'is_full_depth': False})
    locations = set()
    for row in dataset['locations']:
        require(set(row) == {'key', 'description'} and re.fullmatch(r'pilot-location-\d{2,5}', row['key'])
                and row['description'] == 'Synthetic acceptance fixture', 'location_shape')
        locations.add(row['key'])
        add(row['key'], 'dcim.location', {'name': row['key']},
            {'location_type': ref('location_type'), 'status': ref('status'), 'description': row['description'], 'parent': None})
    interfaces = set()
    for row in dataset['devices']:
        require(set(row) == {'key', 'location', 'interfaces'} and re.fullmatch(r'pilot-device-\d{4,5}', row['key'])
                and row['location'] in locations and 0 < len(row['interfaces']) <= 65000, 'device_shape')
        # Global name lookup refuses collisions even in a different Location.
        add(row['key'], 'dcim.device', {'name': row['key']},
            {'device_type': ref('device_type'), 'role': ref('role'), 'status': ref('status'), 'location': ref(row['location'])})
        for interface in row['interfaces']:
            require(set(interface) == {'name', 'enabled'} and re.fullmatch(r'eth\d{1,5}', interface['name'])
                    and interface['enabled'] is True, 'interface_shape')
            key = row['key'] + '/' + interface['name']
            interfaces.add(key)
            add(key, 'dcim.interface', {'device': ref(row['key']), 'name': interface['name']},
                {'type': 'virtual', 'enabled': True, 'status': ref('status')})
    prefixes, assigned = set(), set()
    for row in dataset['ip_assignments']:
        require(set(row) == {'device', 'interface', 'address'}, 'assignment_shape')
        key = row['device'] + '/' + row['interface']
        address = ipaddress.ip_interface(row['address'])
        require(key in interfaces and key not in assigned and address.version == 4 and address.network.prefixlen == 24
                and address.ip in ipaddress.ip_network('198.18.0.0/15') and str(address) == row['address'], 'assignment_scope')
        assigned.add(key)
        prefix = str(address.network)
        if prefix not in prefixes:
            add(prefix, 'ipam.prefix', {'namespace': ref('namespace'), 'network': str(address.network.network_address), 'prefix_length': 24},
                {'status': ref('status'), 'type': 'network'})
            prefixes.add(prefix)
        add(row['address'], 'ipam.ipaddress', {'parent': ref(prefix), 'host': str(address.ip)},
            {'mask_length': 24, 'status': ref('status'), 'type': 'host'})
        add('assignment/' + key, 'ipam.ipaddresstointerface', {'ip_address': ref(row['address']), 'interface': ref(key)})
    return nodes


def apply(dataset, store, receipt=None, write=False):
    """Atomic initial import or strict verification; repeat imports never repair drift.

    The returned UUID receipt must be preserved and reviewed before a second run.
    A lost receipt blocks adoption of existing objects, even with matching names.
    """
    require(len(canonical(dataset)) <= 4194304, 'fixture_size')
    nodes = plan(dataset)
    digest = hashlib.sha256(canonical(dataset)).hexdigest()
    if receipt is not None:
        require(set(receipt) == {'schema_version', 'fixture_sha256', 'objects'} and receipt['schema_version'] == 1
                and receipt['fixture_sha256'] == digest and set(receipt['objects']) == {n['key'] for n in nodes}, 'ownership_receipt')
    require(write or receipt is not None, 'ownership_required')
    objects, ids, observed = {}, {}, []
    with store.transaction(write):
        for node in nodes:
            def resolve(fields):
                return {k: objects[v['ref']] if isinstance(v, dict) else v for k, v in fields.items()}
            lookup, fields = resolve(node['lookup']), resolve(node['fields'])
            found = store.find(node['model'], lookup)
            require(len(found) <= 1, 'ambiguous_object')
            if found:
                obj = found[0]
                require(receipt is not None and receipt['objects'][node['key']] == store.identity(obj), 'unowned_object')
            else:
                require(write and receipt is None, 'owned_object_missing')
                obj = store.create(node['model'], {**lookup, **fields}, node['content_types'])
            require(store.matches(obj, {**lookup, **fields}, node['content_types']), 'owned_object_drift')
            objects[node['key']], ids[node['key']] = obj, store.identity(obj)
            # The normalized projection is emitted only after field readback.
            observed.append(node)
        store.check_membership(objects, nodes)
    normalized = sorted(observed, key=lambda x: x['key'])
    return {'receipt': {'schema_version': 1, 'fixture_sha256': digest, 'objects': ids},
            'normalized': normalized, 'sha256': hashlib.sha256(canonical(normalized)).hexdigest(),
            'counts': {m: sum(n['model'] == m for n in nodes) for m in sorted({n['model'] for n in nodes})}}


class DjangoStore:
    def __init__(self):
        import nautobot
        require(nautobot.__version__ == '3.2.3', 'nautobot_version')
        from django.apps import apps
        self.model = apps.get_model

    def transaction(self, write):
        from contextlib import contextmanager
        from django.db import connection, transaction

        @contextmanager
        def scope():
            with transaction.atomic():
                with connection.cursor() as cursor:
                    cursor.execute("SET LOCAL lock_timeout = '5s'")
                    cursor.execute("SET LOCAL statement_timeout = '60s'")
                    cursor.execute('SELECT pg_advisory_xact_lock' + ('' if write else '_shared') + '(78310923)')
                yield
        return scope()

    def find(self, model, lookup):
        return list(self.model(model).objects.filter(**lookup)[:2])

    def create(self, model, fields, content_types):
        values = dict(fields)
        if model == 'ipam.prefix':
            values['prefix'] = str(values.pop('network')) + '/' + str(values.pop('prefix_length'))
        elif model == 'ipam.ipaddress':
            values['address'] = str(values.pop('host')) + '/' + str(values.pop('mask_length'))
        obj = self.model(model)(**values)
        obj.validated_save()
        if content_types is not None:
            from django.contrib.contenttypes.models import ContentType
            obj.content_types.set([ContentType.objects.get_for_model(self.model(m)) for m in content_types])
        return obj

    @staticmethod
    def identity(obj):
        return str(obj.pk)

    def matches(self, obj, fields, content_types):
        obj.refresh_from_db()
        for name, expected in fields.items():
            actual = getattr(obj, name)
            if hasattr(expected, 'pk'):
                if actual != expected:
                    return False
            elif str(actual) != str(expected):
                return False
        if content_types is not None:
            actual = {f'{ct.app_label}.{ct.model}' for ct in obj.content_types.all()}
            if actual != set(content_types):
                return False
        return True

    def check_membership(self, objects, nodes):
        scopes = {
            'dcim.location': {'location_type': objects['location_type']},
            'dcim.device': {'device_type': objects['device_type']},
            'dcim.interface': {'device__device_type': objects['device_type']},
            'ipam.prefix': {'namespace': objects['namespace']},
            'ipam.ipaddress': {'parent__namespace': objects['namespace']},
            'ipam.ipaddresstointerface': {'ip_address__parent__namespace': objects['namespace']},
        }
        for model, lookup in scopes.items():
            from django.db.models import Q
            scope = Q(**lookup)
            if model == 'ipam.ipaddresstointerface':
                scope |= Q(interface__device__device_type=objects['device_type'])
            actual = {str(pk) for pk in self.model(model).objects.filter(scope).values_list('pk', flat=True)}
            expected = {str(objects[n['key']].pk) for n in nodes if n['model'] == model}
            require(actual == expected, 'fixture_membership')
