require 'miasma'

module Miasma
  module Models
    class Orchestration
      class Aws < Orchestration

        # Extended stack model to provide AWS specific stack options
        class Stack < Orchestration::Stack
          attribute :stack_policy_body, Hash, :coerce => lambda{|v| MultiJson.load(v).to_smash}
          attribute :stack_policy_url, String
        end

        # Service name of the API
        API_SERVICE = 'cloudformation'
        # Service name of the eucalyptus API
        EUCA_API_SERVICE = 'CloudFormation'
        # Supported version of the AutoScaling API
        API_VERSION = '2010-05-15'

        # Valid stack lookup states
        STACK_STATES = [
          "CREATE_COMPLETE", "CREATE_FAILED", "CREATE_IN_PROGRESS", "DELETE_FAILED",
          "DELETE_IN_PROGRESS", "ROLLBACK_COMPLETE", "ROLLBACK_FAILED", "ROLLBACK_IN_PROGRESS",
          "UPDATE_COMPLETE", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_IN_PROGRESS",
          "UPDATE_ROLLBACK_COMPLETE", "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_ROLLBACK_FAILED",
          "UPDATE_ROLLBACK_IN_PROGRESS"
        ]

        include Contrib::AwsApiCore::ApiCommon
        include Contrib::AwsApiCore::RequestUtils

        # @return [Smash] external to internal resource mapping
        RESOURCE_MAPPING = Smash.new(
          'AWS::EC2::Instance' => Smash.new(
            :api => :compute,
            :collection => :servers
          ),
          'AWS::ElasticLoadBalancing::LoadBalancer' => Smash.new(
            :api => :load_balancer,
            :collection => :balancers
          ),
          'AWS::AutoScaling::AutoScalingGroup' => Smash.new(
            :api => :auto_scale,
            :collection => :groups
          ),
          'AWS::CloudFormation::Stack' => Smash.new(
            :api => :orchestration,
            :collection => :stacks
          )
        )

        # Fetch stacks or update provided stack data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack>]
        def load_stack_data(stack=nil)
          d_params = Smash.new('Action' => 'DescribeStacks')
          l_params = Smash.new('Action' => 'ListStacks')
          STACK_STATES.each_with_index do |state, idx|
            l_params["StackStatusFilter.member.#{idx + 1}"] = state.to_s.upcase
          end
          if(stack)
            d_params['StackName'] = stack.id
            descriptions = all_result_pages(nil, :body, 'DescribeStacksResponse', 'DescribeStacksResult', 'Stacks', 'member') do |options|
              request(
                :path => '/',
                :form => options.merge(d_params),
                :method => :post
              )
            end
            policy = request(
              :path => '/',
              :method => :get,
              :params => Smash.new(
                'Action' => 'GetStackPolicy',
                'StackName' => stack.id
              )
            ).get(:body, 'GetStackPolicyResult', 'StackPolicyBody')
            if(policy)
              descriptions.first[:stack_policy] = MultiJson.load(policy).to_smash
            end
          else
            descriptions = []
          end
          lists = all_result_pages(nil, :body, 'ListStacksResponse', 'ListStacksResult', 'StackSummaries', 'member') do |options|
            request(
              :path => '/',
              :form => options.merge(l_params),
              :method => :post
            )
          end.map do |stk|
            desc = descriptions.detect do |d_stk|
              d_stk['StackId'] == stk['StackId']
            end || Smash.new
            stk.merge!(desc)
            if(stack)
              next if stack.id != stk['StackId'] && stk['StackId'].split('/')[1] != stack.id
            end
            state = stk['StackStatus'].downcase.to_sym
            unless(Miasma::Models::Orchestration::VALID_RESOURCE_STATES.include?(state))
              parts = state.to_s.split('_')
              state = [parts.first, *parts.slice(-2, parts.size)].join('_').to_sym
              unless(Miasma::Models::Orchestration::VALID_RESOURCE_STATES.include?(parts))
                state = :unknown
              end
            end
            new_stack = stack || Stack.new(self)
            new_stack.load_data(
              :id => stk['StackId'],
              :name => stk['StackName'],
              :capabilities => [stk.get('Capabilities', 'member')].flatten(1).compact,
              :description => stk['Description'],
              :created => stk['CreationTime'],
              :updated => stk['LastUpdatedTime'],
              :notification_topics => [stk.get('NotificationARNs', 'member')].flatten(1).compact,
              :timeout_in_minutes => stk['TimeoutInMinutes'] ? stk['TimeoutInMinutes'].to_i : nil,
              :status => stk['StackStatus'],
              :status_reason => stk['StackStatusReason'],
              :state => state,
              :template_description => stk['TemplateDescription'],
              :disable_rollback => !!stk['DisableRollback'],
              :outputs => [stk.get('Outputs', 'member')].flatten(1).compact.map{|o|
                Smash.new(
                  :key => o['OutputKey'],
                  :value => o['OutputValue'],
                  :description => o['Description']
                )
              },
              :tags => Smash[
                [stk.fetch('Tags', 'member', [])].flatten(1).map{|param|
                  [param['Key'], param['Value']]
                }
              ],
              :parameters => Smash[
                [stk.fetch('Parameters', 'member', [])].flatten(1).map{|param|
                  [param['ParameterKey'], param['ParameterValue']]
                }
              ],
              :custom => Smash.new(
                :stack_policy_body => policy
              )
            ).valid_state
          end
        end

        # Save the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_save(stack)
          params = Smash.new('StackName' => stack.name)
          (stack.parameters || {}).each_with_index do |pair, idx|
            params["Parameters.member.#{idx + 1}.ParameterKey"] = pair.first
            params["Parameters.member.#{idx + 1}.ParameterValue"] = pair.last
          end
          (stack.capabilities || []).each_with_index do |cap, idx|
            params["Capabilities.member.#{idx + 1}"] = cap
          end
          (stack.notification_topics || []).each_with_index do |topic, idx|
            params["NotificationARNs.member.#{idx + 1}"] = topic
          end
          (stack.tags || {}).each_with_index do |tag, idx|
            params["Tags.member.#{idx + 1}.Key"] = tag.first
            params["Tags.member.#{idx + 1}.Value"] = tag.last
          end
          if(stack.custom[:stack_policy_body])
            params['StackPolicyBody'] = MultiJson.dump(stack.custom[:stack_policy_body])
          end
          if(stack.custom[:stack_policy_url])
            params['StackPolicyURL'] = stack.custom[:stack_policy_url]
          end
          unless(stack.disable_rollback.nil?)
            params['OnFailure'] = stack.disable_rollback ? 'DO_NOTHING' : 'ROLLBACK'
          end
          if(stack.on_failure)
            params['OnFailure'] = stack.on_failure == 'nothing' ? 'DO_NOTHING' : stack.on_failure.upcase
          end
          if(stack.template.empty?)
            params['UsePreviousTemplate'] = true
          else
            params['TemplateBody'] = MultiJson.dump(stack.template)
          end
          if(stack.persisted?)
            result = request(
              :path => '/',
              :method => :post,
              :form => Smash.new(
                'Action' => 'UpdateStack'
              ).merge(params)
            )
            stack
          else
            if(stack.timeout_in_minutes)
              params['TimeoutInMinutes'] = stack.timeout_in_minutes
            end
            result = request(
              :path => '/',
              :method => :post,
              :form => Smash.new(
                'Action' => 'CreateStack'
              ).merge(params)
            )
            stack.id = result.get(:body, 'CreateStackResponse', 'CreateStackResult', 'StackId')
            stack.valid_state
          end
        end

        # Reload the stack data from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_reload(stack)
          if(stack.persisted?)
            ustack = Stack.new(self)
            ustack.id = stack.id
            load_stack_data(ustack)
            if(ustack.data[:name])
              stack.load_data(ustack.attributes).valid_state
            else
              stack.status = 'DELETE_COMPLETE'
              stack.state = :delete_complete
              stack.valid_state
            end
          end
          stack
        end

        # Delete the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [TrueClass, FalseClass]
        def stack_destroy(stack)
          if(stack.persisted?)
            request(
              :path => '/',
              :params => Smash.new(
                'Action' => 'DeleteStack',
                'StackName' => stack.id
              )
            )
            true
          else
            false
          end
        end

        # Fetch stack template
        #
        # @param stack [Stack]
        # @return [Smash] stack template
        def stack_template_load(stack)
          if(stack.persisted?)
            result = request(
              :path => '/',
              :params => Smash.new(
                'Action' => 'GetTemplate',
                'StackName' => stack.id
              )
            )
            MultiJson.load(
              result.get(:body, 'GetTemplateResponse', 'GetTemplateResult', 'TemplateBody')
            ).to_smash
          else
            Smash.new
          end
        end

        # Validate stack template
        #
        # @param stack [Stack]
        # @return [NilClass, String] nil if valid, string error message if invalid
        def stack_template_validate(stack)
          begin
            result = request(
              :method => :post,
              :path => '/',
              :form => Smash.new(
                'Action' => 'ValidateTemplate',
                'TemplateBody' => MultiJson.dump(stack.template)
              )
            )
            nil
          rescue Error::ApiError::RequestError => e
            MultiXml.parse(e.response.body.to_s).to_smash.get(
              'ErrorResponse', 'Error', 'Message'
            )
          end
        end

        # Return single stack
        #
        # @param ident [String] name or ID
        # @return [Stack]
        def stack_get(ident)
          i = Stack.new(self)
          i.id = ident
          i.reload
          i.name ? i : nil
        end

        # Return all stacks
        #
        # @param options [Hash] filter
        # @return [Array<Models::Orchestration::Stack>]
        # @todo check if we need any mappings on state set
        def stack_all
          load_stack_data
        end

        # Return all resources for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Resource>]
        def resource_all(stack)
          results = all_result_pages(nil, :body, 'DescribeStackResourcesResponse', 'DescribeStackResourcesResult', 'StackResources', 'member') do |options|
            request(
              :path => '/',
              :method => :post,
              :form => options.merge(
                Smash.new(
                  'Action' => 'DescribeStackResources',
                  'StackName' => stack.id
                )
              )
            )
          end.map do |res|
            Stack::Resource.new(
              stack,
              :id => res['PhysicalResourceId'],
              :name => res['LogicalResourceId'],
              :logical_id => res['LogicalResourceId'],
              :type => res['ResourceType'],
              :state => res['ResourceStatus'].downcase.to_sym,
              :status => res['ResourceStatus'],
              :status_reason => res['ResourceStatusReason'],
              :updated => res['Timestamp']
            ).valid_state
          end
        end

        # Reload the stack resource data from the API
        #
        # @param resource [Models::Orchestration::Stack::Resource]
        # @return [Models::Orchestration::Resource]
        def resource_reload(resource)
          resource.stack.resources.reload
          resource.stack.resources.get(resource.id)
        end

        # Return all events for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all(stack, evt_id=nil)
          results = all_result_pages(nil, :body, 'DescribeStackEventsResponse', 'DescribeStackEventsResult', 'StackEvents', 'member') do |options|
            request(
              :path => '/',
              :method => :post,
              :form => options.merge(
                'Action' => 'DescribeStackEvents',
                'StackName' => stack.id
              )
            )
          end
          events = results.map do |event|
            Stack::Event.new(
              stack,
              :id => event['EventId'],
              :resource_id => event['PhysicalResourceId'],
              :resource_name => event['LogicalResourceId'],
              :resource_logical_id => event['LogicalResourceId'],
              :resource_state => event['ResourceStatus'].downcase.to_sym,
              :resource_status => event['ResourceStatus'],
              :resource_status_reason => event['ResourceStatusReason'],
              :time => Time.parse(event['Timestamp'])
            ).valid_state
          end
          if(evt_id)
            idx = events.index{|d| e.id == evt_id}
            idx = idx ? idx + 1 : 0
            events.slice(idx, events.size)
          else
            events
          end
        end

        # Return all new events for event collection
        #
        # @param events [Models::Orchestration::Stack::Events]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all_new(events)
          event_all(events.stack, events.all.first.id)
        end

        # Reload the stack event data from the API
        #
        # @param resource [Models::Orchestration::Stack::Event]
        # @return [Models::Orchestration::Event]
        def event_reload(event)
          event.stack.events.reload
          event.stack.events.get(event.id)
        end

      end
    end
  end
end
