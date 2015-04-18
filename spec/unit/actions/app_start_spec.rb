require 'spec_helper'
require 'actions/app_start'

module VCAP::CloudController
  describe AppStart do
    let(:user) { double(:user, guid: '7') }
    let(:user_email) { '1@2.3' }
    let(:app_start) { AppStart.new(user, user_email) }

    describe '#start' do
      let(:environment_variables) { { 'FOO' => 'bar' } }
      let(:diego) { false }
      let(:process1) { AppFactory.make(state: 'STOPPED') }
      let(:process2) { AppFactory.make(state: 'STOPPED') }

      let(:app_model) do
        AppModel.make({
          diego: diego,
          desired_state: 'STOPPED',
          desired_droplet_guid: droplet_guid,
          environment_variables: environment_variables
        })
      end

      before do
        app_model.add_process(process1)
        app_model.add_process(process2)
      end

      context 'when the desired_droplet does not exist' do
        let(:droplet_guid) { nil }

        it 'raises a DropletNotFound exception' do
          expect {
            app_start.start(app_model)
          }.to raise_error(AppStart::DropletNotFound)
        end
      end

      context 'when the desired_droplet exists' do
        let(:droplet) { DropletModel.make }
        let(:droplet_guid) { droplet.guid }

        it 'sets the desired state on the app' do
          app_start.start(app_model)
          expect(app_model.desired_state).to eq('STARTED')
        end

        it 'creates an audit event' do
          expect_any_instance_of(Repositories::Runtime::AppEventRepository).to receive(:record_app_start).with(
            app_model,
            user,
            user_email
          )

          app_start.start(app_model)
        end

        context 'and the droplet has a package' do
          let(:droplet) { DropletModel.make(package_guid: package.guid) }
          let(:package) { PackageModel.make(package_hash: 'some-awesome-thing', state: PackageModel::READY_STATE) }

          it 'sets the package hash correctly on the process' do
            app_start.start(app_model)
            app_model.processes.each do |process|
              expect(process.package_hash).to eq(package.package_hash)
              expect(process.package_state).to eq('STAGED')
            end
          end
        end

        context 'and the droplet does not have a package' do
          it 'sets the package hash to unknown' do
            app_start.start(app_model)
            app_model.processes.each do |process|
              expect(process.package_hash).to eq('unknown')
              expect(process.package_state).to eq('STAGED')
            end
          end
        end

        it 'prepares the sub-processes of the app' do
          app_start.start(app_model)
          expect(app_model.processes.length).to eq(2)
          app_model.processes.each do |process|
            expect(process.needs_staging?).to eq(false)
            expect(process.started?).to eq(true)
            expect(process.state).to eq('STARTED')
            expect(process.diego).to be_falsey
            expect(process.environment_json).to eq(app_model.environment_variables)
          end
        end

        context 'when the diego flag is set to true on the app' do
          let(:diego) { true }
          it 'sets the diego flag to true on the processes' do
            app_start.start(app_model)
            app_model.processes.each do |process|
              expect(process.needs_staging?).to eq(false)
              expect(process.started?).to eq(true)
              expect(process.diego).to be_truthy
              expect(process.state).to eq('STARTED')
              expect(process.environment_json).to eq(app_model.environment_variables)
            end
          end
        end
      end
    end
  end
end
