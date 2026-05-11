CfhighlanderTemplate do

  Name 'aurora-postgres'

  DependsOn 'lib-iam@0.2.0'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']
    ComponentParam 'DnsDomain'
    ComponentParam 'SnapshotID'
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'KmsKeyId' if (defined? kms) && (kms)
    ComponentParam 'GlobalClusterIdentifier', ''

    if defined?(engine_mode) && engine_mode == 'serverless'
      ComponentParam 'MaxCapacity', '2'
      ComponentParam 'MinCapacity', '0.5'
      ComponentParam 'EnableHttpEndpoint', 'false', allowedValues: ['true', 'false']
    else
      ComponentParam 'WriterInstanceType'
      ComponentParam 'ReaderInstanceType'
      ComponentParam 'EnableReader', 'false', allowedValues: ['true', 'false']
    end
    
    ComponentParam 'NamespaceId' if defined? service_discovery
    ComponentParam 'EnhancedMonitoringInterval', '0', allowedValues: ['0', '1', '5', '10', '15', '30', '60']
  end

end
