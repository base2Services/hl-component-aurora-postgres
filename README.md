# aurora (Postgres) CfHighlander component
## Parameters

| Name | Use | Default | Global | Type | Allowed Values |
| ---- | --- | ------- | ------ | ---- | -------------- |
| EnvironmentName | Tagging | dev | true | string
| EnvironmentType | Tagging | development | true | string | ['development','production']
| VPCId | Security Groups | None | false | AWS::EC2::VPC::Id
| DnsDomain | DNS domain to use | None | true | string
| SubnetIds | List of subnets | None | false | CommaDelimitedList
| KmsKeyId | KMS ID | None | false | string (arn)
| NamespaceId | Service discovery namespace ID | None | false | string
| SnapshotId | Snapshot ID to provision from | None | false | string
| WriterInstanceType | Writer instance type *if engine is set to provisioned* | None | false | string
| ReaderInstanceType | Reader instance type *if engine is set to provisioned* | None | false | string
| EnhancedMonitoringInterval | Enhanced Monitoring granularity in seconds. Set to 0 to disable. | 0 | false | string | ['0','1','5','10','15','30','60']
## Outputs/Exports

| Name | Value | Exported |
| ---- | ----- | -------- |
| SecurityGroup | Security Group name | true
| ServiceRegistry | CloudMap service registry ID | true
| DBClusterId | Database Cluster ID | true

## Included Components

[lib-ec2](https://github.com/theonestack/hl-component-lib-ec2)

## Example Configuration
### Highlander
```
  Component name:'database', template: 'aurora-postgres' do
    parameter name: 'DnsDomain', value: root_domain
    parameter name: 'DnsFormat', value: FnSub("${EnvironmentName}.#{root_domain}")
    parameter name: 'SubnetIds', value: cfout('vpcv2', 'PersistenceSubnets')
    parameter name: 'WriterInstanceType', value: writer_instance
    parameter name: 'ReaderInstanceType', value: reader_instance
    parameter name: 'EnableReader', value: 'true'
    parameter name: 'StackOctet', value: '80'
    parameter name: 'NamespaceId', value: cfout('servicediscovery', 'NamespaceId')
  end
```

### Aurora Postgres Configuration
```
hostname: db
database_name: appdb
dns_format: ${DnsFormat}

storage_encrypted: true
engine: aurora-postgres
engine_version: '13.4'

writer_instance: db.r3.large
reader_instance: db.r3.large

master_login: 
    username_ssm_param: /${EnvironmentName}/myapp/dbuser
    password_ssm_param: /${EnvironmentName}/myapp/dbpass

security_group:
  -
    rules:
      -
        IpProtocol: tcp
        FromPort: 5432
        ToPort: 5432
    ips:
      - stack
      - company_office
      - company_client_vpn

service_discovery:
  name: db
```

## Enhanced Monitoring

RDS Enhanced Monitoring provides OS-level metrics (CPU, memory, file system, disk I/O) at up to per-second granularity.

Enable at deploy time by setting the `EnhancedMonitoringInterval` parameter:

```bash
EnhancedMonitoringInterval=60
```

When enabled, the component creates an IAM role with the `AmazonRDSEnhancedMonitoringRole` managed policy and configures monitoring on all DB instances (writer, reader, serverless). Set to `0` to disable (default).

## Cfhighlander Setup

install cfhighlander [gem](https://github.com/theonestack/cfhighlander)

```bash
gem install cfhighlander
```

or via docker

```bash
docker pull theonestack/cfhighlander
```
## Testing Components

Running the tests

```bash
cfhighlander cftest aurora-postgres
```