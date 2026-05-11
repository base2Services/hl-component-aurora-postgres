require 'yaml'

describe 'compiled component aurora-postgres' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/enhanced_monitoring.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/enhanced_monitoring/aurora-postgres.compiled.yaml") }

  context "Condition" do
    context "EnableEnhancedMonitoring" do
      let(:condition) { template["Conditions"]["EnableEnhancedMonitoring"] }

      it "is based on EnhancedMonitoringInterval parameter not being 0" do
        expect(condition).to eq({"Fn::Not"=>[{"Fn::Equals"=>[{"Ref"=>"EnhancedMonitoringInterval"}, "0"]}]})
      end
    end
  end

  context "Parameter" do
    context "EnhancedMonitoringInterval" do
      let(:parameter) { template["Parameters"]["EnhancedMonitoringInterval"] }

      it "exists" do
        expect(parameter).not_to be_nil
      end

      it "has default value of 0" do
        expect(parameter["Default"]).to eq("0")
      end

      it "has allowed values" do
        expect(parameter["AllowedValues"]).to eq(["0", "1", "5", "10", "15", "30", "60"])
      end
    end
  end

  context "Resource" do

    context "EnhancedMonitoringRole" do
      let(:resource) { template["Resources"]["EnhancedMonitoringRole"] }

      it "is of type AWS::IAM::Role" do
        expect(resource["Type"]).to eq("AWS::IAM::Role")
      end

      it "has condition EnableEnhancedMonitoring" do
        expect(resource["Condition"]).to eq("EnableEnhancedMonitoring")
      end

      it "has monitoring.rds.amazonaws.com as the service principal" do
        statement = resource["Properties"]["AssumeRolePolicyDocument"]["Statement"][0]
        expect(statement["Principal"]["Service"]).to eq("monitoring.rds.amazonaws.com")
      end

      it "has the AmazonRDSEnhancedMonitoringRole managed policy" do
        expect(resource["Properties"]["ManagedPolicyArns"]).to include("arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole")
      end
    end

    context "DBClusterInstanceWriter" do
      let(:resource) { template["Resources"]["DBClusterInstanceWriter"] }

      it "has MonitoringInterval with Fn::If" do
        expect(resource["Properties"]["MonitoringInterval"]).to eq({
          "Fn::If" => ["EnableEnhancedMonitoring", {"Ref" => "EnhancedMonitoringInterval"}, {"Ref" => "AWS::NoValue"}]
        })
      end

      it "has MonitoringRoleArn with Fn::If" do
        expect(resource["Properties"]["MonitoringRoleArn"]).to eq({
          "Fn::If" => ["EnableEnhancedMonitoring", {"Fn::GetAtt" => ["EnhancedMonitoringRole", "Arn"]}, {"Ref" => "AWS::NoValue"}]
        })
      end
    end

    context "DBClusterInstanceReader" do
      let(:resource) { template["Resources"]["DBClusterInstanceReader"] }

      it "has MonitoringInterval with Fn::If" do
        expect(resource["Properties"]["MonitoringInterval"]).to eq({
          "Fn::If" => ["EnableEnhancedMonitoring", {"Ref" => "EnhancedMonitoringInterval"}, {"Ref" => "AWS::NoValue"}]
        })
      end

      it "has MonitoringRoleArn with Fn::If" do
        expect(resource["Properties"]["MonitoringRoleArn"]).to eq({
          "Fn::If" => ["EnableEnhancedMonitoring", {"Fn::GetAtt" => ["EnhancedMonitoringRole", "Arn"]}, {"Ref" => "AWS::NoValue"}]
        })
      end
    end

  end

end
