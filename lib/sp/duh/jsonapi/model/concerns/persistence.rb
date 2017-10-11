module SP
  module Duh
    module JSONAPI
      module Model
        module Concerns
          module Persistence
            extend ::ActiveSupport::Concern

            included do

              # Idem for data adapter configuration...
              # In a similar way to ActiveRecord::Base.connection, the adapter should be defined at the base level and is inherited by all subclasses
              class_attribute :adapter, instance_reader: false, instance_writer: false

              self.autogenerated_id = true

              attr_accessible :id
            end

            module ClassMethods

              # Define resource configuration accessors at the class (and subclass) level (static).
              # These attribute values are NOT inherited by subclasses, each subclass MUST define their own.
              # Instances can access these attributes at the class level only.
              attr_accessor :resource_name
              attr_accessor :autogenerated_id

              def find!(id, conditions = nil) ; get(id, conditions) ; end

              def find_explicit!(exp_accounting_schema, exp_accounting_prefix, id, conditions = nil)
                get_explicit(exp_accounting_schema, exp_accounting_prefix, id, conditions)
              end

              def find(id, conditions = nil)
                begin
                  get(id, conditions)
                rescue Exception => e
                  return nil
                end
              end

              def query!(condition) ; get_all(condition) ; end
              def query_explicit!(exp_accounting_schema, exp_accounting_prefix, condition) ; get_all_explicit(exp_accounting_schema, exp_accounting_prefix, condition) ; end

              def query(condition)
                begin
                  get_all(condition)
                rescue Exception => e
                  nil
                end
              end

              def first!(condition = "")
                condition += (condition.blank? ? "" : "&") + "page[size]=1"
                get_all(condition).first
              end

              def first(condition = "")
                begin
                  condition += (condition.blank? ? "" : "&") + "page[size]=1"
                  get_all(condition).first
                rescue Exception => e
                  nil
                end
              end

              def all! ; get_all("") ; end

              def all
                begin
                  get_all("")
                rescue Exception => e
                  nil
                end
              end

              private

                def get_explicit(exp_accounting_schema, exp_accounting_prefix, id, conditions = nil)
                  result = self.adapter.get_explicit!(exp_accounting_schema, exp_accounting_prefix, "#{self.resource_name}/#{id.to_s}", conditions)
                  jsonapi_result_to_instance(result[:data], result)
                end

                def get(id, conditions = nil)
                  result = self.adapter.get("#{self.resource_name}/#{id.to_s}", conditions)
                  jsonapi_result_to_instance(result[:data], result)
                end

                def get_all(condition)
                  got = []
                  result = self.adapter.get(self.resource_name, condition)
                  if result
                    got = result[:data].map do |item|
                      data = { data: item }
                      data.merge(included: result[:included]) if result[:included]
                      jsonapi_result_to_instance(item, data)
                    end
                  end
                  got
                end

                def get_all_explicit(exp_accounting_schema, exp_accounting_prefix, condition)
                  got = []
                  result = self.adapter.get_explicit!(exp_accounting_schema, exp_accounting_prefix, self.resource_name, condition)
                  if result
                    got = result[:data].map do |item|
                      data = { data: item }
                      data.merge(included: result[:included]) if result[:included]
                      jsonapi_result_to_instance(item, data)
                    end
                  end
                  got
                end

                def jsonapi_result_to_instance(result, data)
                  if result
                    instance = self.new(result.merge(result[:attributes]).except(:attributes))
                    instance.send :_data=, data
                  end
                  instance
                end
            end

            # Instance methods

            def new_record?
              if self.class.autogenerated_id || self.id.nil?
                self.id.nil?
              else
                self.class.find(self.id).nil?
              end
            end

            def save!
              if new_record?
                create!
              else
                update!
              end
            end

            def save_explicit!(exp_accounting_schema, exp_accounting_prefix)
              if new_record?
                create!(exp_accounting_schema, exp_accounting_prefix)
              else
                update!(exp_accounting_schema, exp_accounting_prefix)
              end
            end

            def destroy!
              if !new_record?
                self.class.adapter.delete(path_for_id)
              end
            end

            def destroy_explicit!(exp_accounting_schema, exp_accounting_prefix)
              if !new_record?
                self.class.adapter.delete_explicit!(exp_accounting_schema, exp_accounting_prefix, path_for_id)
              end
            end

            alias :delete! :destroy!

            def create!(exp_accounting_schema = nil, exp_accounting_prefix = nil)
              if self.class.autogenerated_id
                params = {
                  data: {
                    type: self.class.resource_name,
                    attributes: get_persistent_json.reject { |k,v| k == :id || v.nil? }
                  }
                }
              else
                params = {
                  data: {
                    type: self.class.resource_name,
                    attributes: get_persistent_json.reject { |k,v| v.nil? }
                  }
                }
              end
              result = if !exp_accounting_schema.blank? || !exp_accounting_prefix.blank?
                self.class.adapter.post_explicit!(exp_accounting_schema, exp_accounting_prefix, self.class.resource_name, params)
              else
                self.class.adapter.post(self.class.resource_name, params)
              end
              # Set the id to the newly created id
              self.id = result[:data][:id]
            end

            def update!(exp_accounting_schema = nil, exp_accounting_prefix = nil)
              params = {
                data: {
                  type: self.class.resource_name,
                  id: self.id.to_s,
                  attributes: get_persistent_json.reject { |k,v| k == :id }
                }
              }
              result = if !exp_accounting_schema.blank? || !exp_accounting_prefix.blank?
                self.class.adapter.patch_explicit!(exp_accounting_schema, exp_accounting_prefix, path_for_id, params)
              else
                self.class.adapter.patch(path_for_id, params)
              end
            end

            def get_persistent_json
              as_json.reject { |k| !k.in?(self.class.attributes) }
            end

            protected

              attr_accessor :_data

            private

              def path_for_id ; "#{self.class.resource_name}/#{self.id.to_s}" ; end

          end
        end
      end
    end
  end
end
