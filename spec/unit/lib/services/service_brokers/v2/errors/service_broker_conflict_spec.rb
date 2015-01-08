require 'spec_helper'

module VCAP::Services
  module ServiceBrokers
    module V2
      module Errors
        describe 'ServiceBrokerConflict' do
          let(:response_body) { '{"message": "error message"}' }
          let(:response) { double(code: 409, reason: 'Conflict', body: response_body) }

          let(:uri) { 'http://uri.example.com' }
          let(:method) { 'POST' }
          let(:error) { StandardError.new }

          it 'initializes the base class correctly' do
            exception = ServiceBrokerConflict.new(uri, method, response)
            expect(exception.message).to eq('error message')
            expect(exception.uri).to eq(uri)
            expect(exception.method).to eq(method)
            expect(exception.source).to eq(MultiJson.load(response.body))
          end

          it 'has a response_code of 409' do
            exception = ServiceBrokerConflict.new(uri, method, response)
            expect(exception.response_code).to eq(409)
          end

          context 'when the response body has no message' do
            let(:response_body) { '{"description": "error description"}' }

            context 'and there is a description field' do
              it 'initializes the base class correctly' do
                exception = ServiceBrokerConflict.new(uri, method, response)
                expect(exception.message).to eq('error description')
                expect(exception.uri).to eq(uri)
                expect(exception.method).to eq(method)
                expect(exception.source).to eq(MultiJson.load(response.body))
              end
            end

            context 'and there is no description field' do
              let(:response_body) { '{"field": "value"}' }

              it 'initializes the base class correctly' do
                exception = ServiceBrokerConflict.new(uri, method, response)
                expect(exception.message).to eq("Resource conflict: #{uri}")
                expect(exception.uri).to eq(uri)
                expect(exception.method).to eq(method)
                expect(exception.source).to eq(MultiJson.load(response.body))
              end
            end
          end

          context 'when the body is not JSON-parsable' do
            let(:response_body) { 'foo' }

            it 'initializes the base class correctly' do
              exception = ServiceBrokerConflict.new(uri, method, response)
              expect(exception.message).to eq("Resource conflict: #{uri}")
              expect(exception.uri).to eq(uri)
              expect(exception.method).to eq(method)
              expect(exception.source).to eq(response.body)
            end
          end
        end
      end
    end
  end
end