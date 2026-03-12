# Migration Strategy

## Cloud Portability

Provider portability is achieved through common OpenTofu module inputs and normalized outputs. Migrations are performed by:

1. Exporting OpenBao data and configuration through the backup workflow.
2. Switching `provider` and provider-specific variables.
3. Applying infrastructure in the target cloud.
4. Running restore and validation scripts.

## Current Target Priority

- Primary: Hetzner
- Secondary: AWS
- Secondary: DigitalOcean

## Constraints

Provider networking models differ. The abstraction preserves operator workflow, not binary-identical infrastructure graphs.
