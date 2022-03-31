CloudFormation do

  Condition("EnableReader", FnEquals(Ref("EnableReader"), 'true'))
  Condition("UseUsernameAndPassword", FnEquals(Ref(:SnapshotID), ''))
  Condition("UseSnapshotID", FnNot(FnEquals(Ref(:SnapshotID), '')))
  Condition("CreateHostRecord", FnNot(FnEquals(Ref(:DnsDomain), '')))
  Condition("CreateReaderRecord", FnAnd([FnEquals(Ref("EnableReader"), 'true'), Condition('CreateHostRecord')]))

  aurora_tags = []
  aurora_tags << { Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") }
  aurora_tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  aurora_tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }
  aurora_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags

  ingress = []
  security_group_rules.each do |rule|
    sg_rule = {
      FromPort: cluster_port,
      IpProtocol: 'TCP',
      ToPort: cluster_port,
    }
    if rule['security_group_id']
      sg_rule['SourceSecurityGroupId'] = FnSub(rule['security_group_id'])
    else
      sg_rule['CidrIp'] = FnSub(rule['ip'])
    end
    if rule['desc']
      sg_rule['Description'] = FnSub(rule['desc'])
    end
    ingress << sg_rule
  end if defined?(security_group_rules)

  EC2_SecurityGroup(:SecurityGroup) do
    VpcId Ref('VPCId')
    GroupDescription FnSub("Aurora postgres #{component_name} access for the ${EnvironmentName} environment")
    SecurityGroupIngress ingress if ingress.any?
    SecurityGroupEgress ([
      {
        CidrIp: "0.0.0.0/0",
        Description: "outbound all for ports",
        IpProtocol: -1,
      }
    ])
    Tags aurora_tags
  end

  Output(:SecurityGroupId) {
    Value(FnGetAtt(:SecurityGroup, :GroupId))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-securitygroup-id")
  }

  RDS_DBSubnetGroup(:DBClusterSubnetGroup) {
    SubnetIds Ref('SubnetIds')
    DBSubnetGroupDescription FnSub("Aurora postgres #{component_name} subnets for the ${EnvironmentName} environment")
    Tags aurora_tags
  }

  RDS_DBClusterParameterGroup(:DBClusterParameterGroup) {
    Description FnSub("Aurora postgres #{component_name} cluster parameters for the ${EnvironmentName} environment")
    Family family
    Parameters cluster_parameters if defined? cluster_parameters
    Tags aurora_tags
  }

  secrets_manager = external_parameters.fetch(:secret_username, false)
  if secrets_manager
    SecretsManager_Secret(:SecretCredentials) {
      GenerateSecretString ({
        SecretStringTemplate: "{\"username\":\"#{secrets_manager}\"}",
        GenerateStringKey: "password",
        ExcludeCharacters: "\"@'`/\\"
      })
    }

    instance_username = FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:username}}' ])
    instance_password = FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:password}}' ])

    Output(:SecretCredentials) {
      Value(Ref(:SecretCredentials))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-Secret")
    }
  else
    instance_username = FnJoin('', [ '{{resolve:ssm:', FnSub(master_login['username_ssm_param']), ':1}}' ])
    instance_password = FnJoin('', [ '{{resolve:ssm-secure:', FnSub(master_login['password_ssm_param']), ':1}}' ])
  end

  RDS_DBCluster(:DBCluster) {
    Engine 'aurora-postgresql'
    EngineVersion engine_version if defined? engine_version
    DBClusterParameterGroupName Ref(:DBClusterParameterGroup)
    SnapshotIdentifier Ref(:SnapshotID)
    SnapshotIdentifier FnIf('UseSnapshotID',Ref(:SnapshotID), Ref('AWS::NoValue'))
    MasterUsername  FnIf('UseUsernameAndPassword', instance_username, Ref('AWS::NoValue'))
    MasterUserPassword  FnIf('UseUsernameAndPassword', instance_password, Ref('AWS::NoValue'))
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    VpcSecurityGroupIds [ Ref(:SecurityGroup) ]
    DatabaseName FnSub(database_name) if defined? database_name
    StorageEncrypted storage_encrypted if defined? storage_encrypted
    KmsKeyId Ref('KmsKeyId') if (defined? kms) && (kms)
    Port cluster_port
    Tags aurora_tags
  }

  RDS_DBParameterGroup(:DBInstanceParameterGroup) {
    Description FnSub("Aurora postgres #{component_name} instance parameters for the ${EnvironmentName} environment")
    Family family
    Parameters instance_parameters if defined? instance_parameters
    Tags aurora_tags
  }

  RDS_DBInstance(:DBClusterInstanceWriter) {
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    DBParameterGroupName Ref(:DBInstanceParameterGroup)
    DBClusterIdentifier Ref(:DBCluster)
    Engine 'aurora-postgresql'
    EngineVersion engine_version if defined? engine_version
    AutoMinorVersionUpgrade minor_upgrade if defined? minor_upgrade
    PreferredMaintenanceWindow maint_window if defined? maint_window
    PubliclyAccessible 'false'
    DBInstanceClass Ref(:WriterInstanceType)
    Tags aurora_tags
  }

  RDS_DBInstance(:DBClusterInstanceReader) {
    Condition(:EnableReader)
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    DBParameterGroupName Ref(:DBInstanceParameterGroup)
    DBClusterIdentifier Ref(:DBCluster)
    Engine 'aurora-postgresql'
    EngineVersion engine_version if defined? engine_version
    PubliclyAccessible 'false'
    DBInstanceClass Ref(:ReaderInstanceType)
    Tags aurora_tags
  }

  Route53_RecordSet(:DBClusterReaderRecord) {
    Condition(:CreateReaderRecord)
    HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
    Name FnJoin('', [ hostname_read_endpoint, '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('DBCluster','ReadEndpoint.Address') ]
  }

  Route53_RecordSet(:DBHostRecord) {
    Condition(:CreateHostRecord)
    HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
    Name FnJoin('', [ hostname, '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('DBCluster','Endpoint.Address') ]
  }

  registry = {}
  service_discovery = external_parameters.fetch(:service_discovery, {})

  unless service_discovery.empty?
    ServiceDiscovery_Service(:ServiceRegistry) {
      NamespaceId Ref(:NamespaceId)
      Name service_discovery['name']  if service_discovery.has_key? 'name'
      DnsConfig({
        DnsRecords: [{
          TTL: 60,
          Type: 'CNAME'
        }],
        RoutingPolicy: 'WEIGHTED'
      })
      if service_discovery.has_key? 'healthcheck'
        HealthCheckConfig service_discovery['healthcheck']
      else
        HealthCheckCustomConfig ({ FailureThreshold: (service_discovery['failure_threshold'] || 1) })
      end
    }

    ServiceDiscovery_Instance(:RegisterInstance) {
      InstanceAttributes(
        AWS_INSTANCE_CNAME: FnGetAtt('DBCluster','Endpoint.Address')
      )
      ServiceId Ref(:ServiceRegistry)
    }

    Output(:ServiceRegistry) {
      Value(Ref(:ServiceRegistry))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-CloudMapService")
    }
  end

  Output(:DBClusterId) {
    Value(Ref(:DBCluster))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-dbcluster-id")
  }

end
