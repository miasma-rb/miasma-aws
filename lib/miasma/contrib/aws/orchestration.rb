require "miasma"

module Miasma
  module Models
    class Orchestration
      # AWS Orchestration API
      class Aws < Orchestration

        # Extended stack model to provide AWS specific stack options
        class Stack < Orchestration::Stack
          attribute :stack_policy_body, Hash, :coerce => lambda { |v| MultiJson.load(v).to_smash }
          attribute :stack_policy_url, String
          attribute :last_event_token, String
        end

        # Service name of the API
        API_SERVICE = "cloudformation".freeze
        # Service name of the eucalyptus API
        EUCA_API_SERVICE = "CloudFormation".freeze
        # Supported version of the AutoScaling API
        API_VERSION = "2010-05-15".freeze

        # Valid stack lookup states
        STACK_STATES = [
          "CREATE_COMPLETE", "CREATE_FAILED", "CREATE_IN_PROGRESS", "DELETE_FAILED",
          "DELETE_IN_PROGRESS", "ROLLBACK_COMPLETE", "ROLLBACK_FAILED", "ROLLBACK_IN_PROGRESS",
          "UPDATE_COMPLETE", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_IN_PROGRESS",
          "UPDATE_ROLLBACK_COMPLETE", "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_ROLLBACK_FAILED",
          "UPDATE_ROLLBACK_IN_PROGRESS",
        ].map(&:freeze).freeze

        include Contrib::AwsApiCore::ApiCommon
        include Contrib::AwsApiCore::RequestUtils

        # @return [Smash] external to internal resource mapping
        RESOURCE_MAPPING = Smash.new(
          "AWS::EC2::Instance" => Smash.new(
            :api => :compute,
            :collection => :servers,
          ),
          "AWS::ElasticLoadBalancing::LoadBalancer" => Smash.new(
            :api => :load_balancer,
            :collection => :balancers,
          ),
          "AWS::AutoScaling::AutoScalingGroup" => Smash.new(
            :api => :auto_scale,
            :collection => :groups,
          ),
          "AWS::CloudFormation::Stack" => Smash.new(
            :api => :orchestration,
            :collection => :stacks,
          ),
        ).to_smash(:freeze)

        # Fetch stacks or update provided stack data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack>]
        def load_stack_data(stack = nil)
          d_params = Smash.new("Action" => "DescribeStacks")
          l_params = Smash.new("Action" => "ListStacks")
          STACK_STATES.each_with_index do |state, idx|
            l_params["StackStatusFilter.member.#{idx + 1}"] = state.to_s.upcase
          end
          if stack
            d_params["StackName"] = stack.id
            descriptions = all_result_pages(nil, :body,
                                            "DescribeStacksResponse", "DescribeStacksResult",
                                            "Stacks", "member") do |options|
              request(
                :method => :post,
                :path => "/",
                :form => options.merge(d_params),
              )
            end
          else
            lists = all_result_pages(nil, :body,
                                     "ListStacksResponse", "ListStacksResult",
                                     "StackSummaries", "member") do |options|
              request(
                :method => :post,
                :path => "/",
                :form => options.merge(l_params),
              )
            end
            descriptions = []
          end
          (lists || descriptions).map do |stk|
            if lists
              desc = descriptions.detect do |d_stk|
                d_stk["StackId"] == stk["StackId"]
              end || Smash.new
              stk.merge!(desc)
            end
            if stack
              next if stack.id != stk["StackId"] && stk["StackId"].split("/")[1] != stack.id
            end
            state = stk["StackStatus"].downcase.to_sym
            unless Miasma::Models::Orchestration::VALID_RESOURCE_STATES.include?(state)
              parts = state.to_s.split("_")
              state = [parts.first, *parts.slice(-2, parts.size)].join("_").to_sym
              unless Miasma::Models::Orchestration::VALID_RESOURCE_STATES.include?(parts)
                state = :unknown
              end
            end
            new_stack = stack || Stack.new(self)
            new_stack.load_data(
              :id => stk["StackId"],
              :name => stk["StackName"],
              :capabilities => [stk.get("Capabilities", "member")].flatten(1).compact,
              :description => stk["Description"],
              :created => stk["CreationTime"],
              :updated => stk["LastUpdatedTime"],
              :notification_topics => [stk.get("NotificationARNs", "member")].flatten(1).compact,
              :timeout_in_minutes => stk["TimeoutInMinutes"] ? stk["TimeoutInMinutes"].to_i : nil,
              :status => stk["StackStatus"],
              :status_reason => stk["StackStatusReason"],
              :state => state,
              :template_description => stk["TemplateDescription"],
              :disable_rollback => !!stk["DisableRollback"],
              :outputs => [stk.get("Outputs", "member")].flatten(1).compact.map { |o|
                Smash.new(
                  :key => o["OutputKey"],
                  :value => o["OutputValue"],
                  :description => o["Description"],
                )
              },
              :tags => Smash[
                [stk.fetch("Tags", "member", [])].flatten(1).map { |param|
                  [param["Key"], param["Value"]]
                }
              ],
              :parameters => Smash[
                [stk.fetch("Parameters", "member", [])].flatten(1).map { |param|
                  [param["ParameterKey"], param["ParameterValue"]]
                }
              ],
              :custom => Smash.new(
                :stack_policy => stk["StackPolicyBody"],
                :stack_policy_url => stk["StackPolicyURL"],
              ),
            ).valid_state
          end
        end

        # Save the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_save(stack)
          params = common_stack_params(stack)
          if stack.custom[:stack_policy_body]
            params["StackPolicyBody"] = MultiJson.dump(stack.custom[:stack_policy_body])
          end
          if stack.custom[:stack_policy_url]
            params["StackPolicyURL"] = stack.custom[:stack_policy_url]
          end
          unless stack.disable_rollback.nil?
            params["OnFailure"] = stack.disable_rollback ? "DO_NOTHING" : "ROLLBACK"
          end
          if stack.on_failure
            params["OnFailure"] = stack.on_failure == "nothing" ? "DO_NOTHING" : stack.on_failure.upcase
          end
          if stack.persisted?
            result = request(
              :path => "/",
              :method => :post,
              :form => Smash.new(
                "Action" => "UpdateStack",
              ).merge(params),
            )
            stack
          else
            if stack.timeout_in_minutes
              params["TimeoutInMinutes"] = stack.timeout_in_minutes
            end
            result = request(
              :path => "/",
              :method => :post,
              :form => Smash.new(
                "Action" => "CreateStack",
              ).merge(params),
            )
            stack.id = result.get(:body, "CreateStackResponse", "CreateStackResult", "StackId")
            stack.valid_state
          end
        end

        # Generate a new stack plan from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        # @todo Needs to include the rolearn and resourcetypes
        #       at some point but more thought on how to integrate
        def stack_plan(stack)
          params = common_stack_params(stack)
          plan_name = changeset_name(stack)
          result = request(
            :path => "/",
            :method => :post,
            :form => params.merge(Smash.new(
              "Action" => "CreateChangeSet",
              "ChangeSetName" => plan_name,
              "StackName" => stack.name,
              "ChangeSetType" => stack.persisted? ? "UPDATE" : "CREATE",
            )),
          )
          stack.reload
          # Ensure we have the same plan name in use after reload
          stack.custom = stack.custom.dup
          stack.custom[:plan_name] = plan_name
          stack.plan
        end

        # Load the plan for the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack::Plan]
        def stack_plan_load(stack)
          if stack.attributes[:plan]
            plan = stack.attributes[:plan]
          else
            plan = Stack::Plan.new(stack, name: changeset_name(stack))
          end
          if stack.custom[:plan_name]
            if stack.custom[:plan_name] != plan.name
              plan.name = stack.custom[:plan_name]
            else
              plan.name = changeset_name(stack)
            end
          end
          result = nil
          Bogo::Retry.build(:linear, max_attempts: 10, wait_interval: 5, ui: Bogo::Ui.new) do
            begin
              result = request(
                :path => "/",
                :method => :post,
                :form => Smash.new(
                  "Action" => "DescribeChangeSet",
                  "ChangeSetName" => plan.name,
                  "StackName" => stack.name,
                ),
              )
            rescue Error::ApiError::RequestError => e
              # Plan does not exist
              if e.response.code == 404
                return nil
              end
              # Stack does not exist
              if e.response.code == 400 && e.message.include?("ValidationError: Stack")
                return nil
              end
              raise
            end
            status = result.get(:body, "DescribeChangeSetResponse", "DescribeChangeSetResult", "ExecutionStatus")
            if status != "AVAILABLE"
              raise "Plan execution is not yet available"
            end
          end.run!
          res = result.get(:body, "DescribeChangeSetResponse", "DescribeChangeSetResult")
          plan.id = res["ChangeSetId"]
          plan.name = res["ChangeSetName"]
          plan.custom = {
            :execution_status => res["ExecutionStatus"],
            :stack_name => res["StackName"],
            :stack_id => res["StackId"],
            :status => res["Status"],
          }
          plan.state = res["ExecutionStatus"].downcase.to_sym
          plan.parameters = Smash[
            [res.get("Parameters", "member")].compact.flatten.map { |param|
              [param["ParameterKey"], param["ParameterValue"]]
            }
          ]
          plan.created_at = res["CreationTime"]
          plan.template = stack_plan_template(plan, :processed)
          items = {:add => [], :replace => [], :remove => [], :unknown => [], :interrupt => []}
          [res.get("Changes", "member")].compact.flatten.each do |chng|
            if chng["Type"] == "Resource"
              item_diffs = []
              [chng.get("ResourceChange", "Details", "member")].compact.flatten.each do |d|
                item_path = [
                  d.get("Target", "Attribute"),
                  d.get("Target", "Name"),
                ].compact
                original_value = stack.template.get("Resources", chng.get("ResourceChange", "LogicalResourceId"), *item_path)
                if original_value.is_a?(Hash) && (stack.parameters || {}).key?(original_value["Ref"])
                  original_value = stack.parameters[original_value["Ref"]]
                end
                new_value = plan.template.get("Resources", chng.get("ResourceChange", "LogicalResourceId"), *item_path)
                if new_value.is_a?(Hash) && plan.parameters.key?(new_value["Ref"])
                  new_value = plan.parameters[new_value["Ref"]]
                end
                diff = Stack::Plan::Diff.new(
                  :name => item_path.join("."),
                  :current => original_value.inspect,
                  :proposed => new_value.inspect,
                )

                unless item_diffs.detect { |d| d.name == diff.name && d.current == diff.current && d.proposed == diff.proposed }
                  item_diffs << diff
                end
              end
              type = case chng.get("ResourceChange", "Action").to_s.downcase
                     when "add"
                       :add
                     when "modify"
                       chng.get("ResourceChange", "Replacement") == "True" ?
                         :replace : :interrupt
                     when "remove"
                       :remove
                     else
                       :unknown
                     end
              items[type] << Stack::Plan::Item.new(
                :name => chng.get("ResourceChange", "LogicalResourceId"),
                :type => chng.get("ResourceChange", "ResourceType"),
                :diffs => item_diffs.sort_by(&:name),
              )
            end
          end.compact
          items.each do |type, list|
            plan.send("#{type}=", list.sort_by(&:name))
          end
          if plan.custom[:stack_id]
            stack.id = plan.custom[:stack_id]
            stack.valid_state
          end
          stack.plan = plan.valid_state
        end

        def stack_plan_template(plan, state)
          result = request(
            :path => "/",
            :method => :post,
            :form => Smash.new(
              "Action" => "GetTemplate",
              "ChangeSetName" => plan.id,
              "TemplateStage" => state.to_s.capitalize,
            ),
          )
          MultiJson.load(result.get(:body, "GetTemplateResponse", "GetTemplateResult", "TemplateBody")).to_smash
        end

        # Delete the plan attached to the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_plan_destroy(stack)
          request(
            :path => "/",
            :method => :post,
            :form => Smash.new(
              "Action" => "DeleteChangeSet",
              "ChangeSetName" => stack.plan.id,
              "StackName" => stack.name,
            ),
          )
          stack.plan = nil
          stack.valid_state
        end

        # Apply the plan attached to the stack
        #
        # @param stack [Model::Orchestration::Stack]
        # @return [Model::Orchestration::Stack]
        def stack_plan_execute(stack)
          request(
            :path => "/",
            :method => :post,
            :form => Smash.new(
              "Action" => "ExecuteChangeSet",
              "ChangeSetName" => stack.plan.id,
              "StackName" => stack.name,
            ),
          )
          stack.reload
        end

        # Reload the plan
        #
        # @param plan [Model::Orchestration::Stack::Plan]
        # @return [Model::Orchestration::Stack::Plan]
        def stack_plan_reload(plan)
          if plan.stack.plan == plan
            stack_plan_load(plan.stack)
          else
            stack = Stack.new(self,
                              id: plan.custom[:stack_id],
                              name: plan.custom[:stack_name])
            stack.dirty[:plan] = plan
            stack_plan_load(stack)
          end
        end

        # Load all plans associated to given stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Plan>]
        def stack_plan_all(stack)
          all_result_pages(nil, :body,
                           "ListChangeSetsResponse", "ListChangeSetsResult",
                           "Summaries", "member") do |options|
            request(
              :method => :post,
              :path => "/",
              :form => options.merge(
                Smash.new(
                  "Action" => "ListChangeSets",
                  "StackName" => stack.id || stack.name,
                )
              ),
            )
          end.map do |res|
            stack = Stack.new(self,
                              id: res["StackId"],
                              name: res["StackName"])
            stack.custom = {:plan_name => res["ChangeSetName"],
                            :plan_id => res["ChangeSetId"]}
            stack.plan
          end
        end

        # Generate changeset name given stack. This
        # is a unique name for miasma and ensures only
        # one changeset is used/persisted for miasma
        # interactions.
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [String]
        def changeset_name(stack)
          stack.custom.fetch(:plan_name, "miasma-changeset-#{stack.name}")
        end

        # Reload the stack data from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_reload(stack)
          if stack.persisted?
            ustack = Stack.new(self)
            ustack.id = stack.id
            load_stack_data(ustack)
            if ustack.data[:name]
              stack.load_data(ustack.attributes).valid_state
            else
              stack.status = "DELETE_COMPLETE"
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
          if stack.persisted?
            request(
              :method => :post,
              :path => "/",
              :form => Smash.new(
                "Action" => "DeleteStack",
                "StackName" => stack.id,
              ),
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
          if stack.persisted?
            result = request(
              :method => :post,
              :path => "/",
              :form => Smash.new(
                "Action" => "GetTemplate",
                "StackName" => stack.id,
              ),
            )
            template = result.get(:body, "GetTemplateResponse", "GetTemplateResult", "TemplateBody")
            template.nil? ? Smash.new : MultiJson.load(template)
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
            if stack.template_url
              params = Smash.new("TemplateURL" => stack.template_url)
            else
              params = Smash.new("TemplateBody" => MultiJson.dump(stack.template))
            end
            result = request(
              :method => :post,
              :path => "/",
              :form => params.merge(
                "Action" => "ValidateTemplate",
              ),
            )
            nil
          rescue Error::ApiError::RequestError => e
            MultiXml.parse(e.response.body.to_s).to_smash.get(
              "ErrorResponse", "Error", "Message"
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
          all_result_pages(nil, :body,
                           "ListStackResourcesResponse", "ListStackResourcesResult",
                           "StackResourceSummaries", "member") do |options|
            request(
              :method => :post,
              :path => "/",
              :form => options.merge(
                Smash.new(
                  "Action" => "ListStackResources",
                  "StackName" => stack.id,
                )
              ),
            )
          end.map do |res|
            Stack::Resource.new(
              stack,
              :id => res["PhysicalResourceId"],
              :name => res["LogicalResourceId"],
              :logical_id => res["LogicalResourceId"],
              :type => res["ResourceType"],
              :state => res["ResourceStatus"].downcase.to_sym,
              :status => res["ResourceStatus"],
              :updated => res["LastUpdatedTimestamp"],
            ).valid_state
          end
        end

        # Reload the stack resource data from the API
        #
        # @param resource [Models::Orchestration::Stack::Resource]
        # @return [Models::Orchestration::Resource]
        def resource_reload(resource)
          result = request(
            :method => :post,
            :path => "/",
            :form => Smash.new(
              "LogicalResourceId" => resource.logical_id,
              "StackName" => resource.stack.name,
            ),
          ).get(:body,
                "DescribeStackResourceResponse", "DescribeStackResourceResult",
                "StackResourceDetail")
          resource.updated = result["LastUpdatedTimestamp"]
          resource.type = result["ResourceType"]
          resource.state = result["ResourceStatus"].downcase.to_sym
          resource.status = result["ResourceStatus"]
          resource.status_reason = result["ResourceStatusReason"]
          resource.valid_state
          resource
        end

        # Return all events for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all(stack, evt_id = nil)
          evt_id = stack.last_event_token if evt_id
          results = all_result_pages(evt_id, :body,
                                     "DescribeStackEventsResponse", "DescribeStackEventsResult",
                                     "StackEvents", "member") do |options|
            request(
              :method => :post,
              :path => "/",
              :form => options.merge(
                "Action" => "DescribeStackEvents",
                "StackName" => stack.id,
              ),
            )
          end
          events = results.map do |event|
            stack.last_event_token = event["NextToken"] if event["NextToken"]
            Stack::Event.new(
              stack,
              :id => event["EventId"],
              :resource_id => event["PhysicalResourceId"],
              :resource_name => event["LogicalResourceId"],
              :resource_logical_id => event["LogicalResourceId"],
              :resource_state => event["ResourceStatus"].downcase.to_sym,
              :resource_status => event["ResourceStatus"],
              :resource_status_reason => event["ResourceStatusReason"],
              :time => Time.parse(event["Timestamp"]),
            ).valid_state
          end
          if evt_id
            idx = events.index { |d| d.id == evt_id }
            idx ? events.slice(0, idx) : events
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

        # Common parameters used for stack creation/update
        # requests. This is currently shared between stack
        # creation and plan creation
        #
        # @param stack [Model::Orchestration::Stack]
        # @return [Smash]
        def common_stack_params(stack)
          params = Smash.new("StackName" => stack.name)
          if stack.dirty?(:parameters)
            initial_parameters = stack.data[:parameters] || {}
          else
            initial_parameters = {}
          end
          (stack.parameters || {}).each_with_index do |pair, idx|
            params["Parameters.member.#{idx + 1}.ParameterKey"] = pair.first
            if initial_parameters[pair.first] == pair.last
              params["Parameters.member.#{idx + 1}.UsePreviousValue"] = true
            else
              params["Parameters.member.#{idx + 1}.ParameterValue"] = pair.last
            end
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
          if stack.template_url
            params["TemplateURL"] = stack.template_url
          elsif !stack.dirty?(:template) && stack.persisted?
            params["UsePreviousTemplate"] = true
          else
            params["TemplateBody"] = MultiJson.dump(stack.template)
          end
          params
        end
      end
    end
  end
end
