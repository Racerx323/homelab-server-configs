"""Candidate Jobs; install/register only in a separately reviewed workload bundle."""
from nautobot.apps.jobs import Job, JSONVar, register_jobs
from workload_adapter import DjangoStore, apply


class PilotImport(Job):
    dataset = JSONVar()
    ownership = JSONVar(required=False)

    class Meta:
        name = 'Homelab pilot import'
        soft_time_limit = 840
        time_limit = 900
        has_sensitive_variables = False

    def run(self, dataset, ownership=None):
        result = apply(dataset, DjangoStore(), receipt=ownership or None, write=True)
        return {k: v for k, v in result.items() if k != 'normalized'}


class PilotExport(Job):
    dataset = JSONVar()
    ownership = JSONVar()

    class Meta:
        name = 'Homelab pilot export'
        read_only = True
        soft_time_limit = 840
        time_limit = 900
        has_sensitive_variables = False

    def run(self, dataset, ownership):
        result = apply(dataset, DjangoStore(), receipt=ownership)
        return {k: v for k, v in result.items() if k != 'receipt'}


class PilotAudit(PilotExport):
    class Meta:
        name = 'Homelab pilot audit'
        read_only = True
        soft_time_limit = 840
        time_limit = 900
        has_sensitive_variables = False

    def run(self, dataset, ownership):
        result = apply(dataset, DjangoStore(), receipt=ownership)
        return {'counts': result['counts'], 'sha256': result['sha256']}


register_jobs(PilotImport, PilotExport, PilotAudit)
