require 'spec_helper'

describe ExtraData, :type => :model do
  describe "detach_extra_data" do
    it 'should schedule if not called with true argument' do
      s = LogSession.new
      expect(s).to receive(:skip_extra_data_processing?).and_return(false)
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      s.id = 14
      s.detach_extra_data
      expect(Worker.scheduled_for?(:slow, LogSession, "perform_action", {'id' => 14, 'method' => 'detach_extra_data', 'arguments' => [true]})).to eq(true)
    end

    it 'should do nothing if extra_data_too_big? is false' do
      s = LogSession.new(data: {'extra_data_nonce' => 'asdf'})
      expect(s).to receive(:assert_extra_data)
      expect(Uploader).to_not receive(:remote_upload)
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      s.detach_extra_data(true)
    end
    
    it 'should force if frd="force" even if not enough data"' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(1).times.and_return(nil)
      s.detach_extra_data('force')
      expect(paths).to eq(['private'])
    end

    it 'should not re-upload if already uploaded the button set with the same revision hash' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u, data: {'extra_data_nonce' => 'qwwqtqw', 'extra_data_revision' => 'asdf', 'full_set_revision' => 'asdf'})
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      expect(Uploader).to_not receive(:remote_upload)
      s.detach_extra_data('force')
    end

    it 'should not re-upload for a different revision hash but same checksum' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u, data: {'extra_data_nonce' => 'qwwqtqw', 'extra_data_revision' => 'asdf', 'full_set_revision' => 'asdf', 'events' => [{'a' => 1}, {'b' => 2}]})
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      res = {}
      expect(Uploader).to receive(:remote_upload) do |path|
        res[:path] = path
      end.and_return(res)
      s.data['full_set_revision'] = 'asdfjkl'
      s.detach_extra_data('force')
      expect(s.data['extra_data_private_path']).to eq(nil)
    end
    
    it 'should upload to a different path if the checksum does not match the existing upload' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u, data: {'extra_data_nonce' => 'qwwqtqw', 'extra_data_revision' => 'asdf', 'full_set_revision' => 'asdf', 'events' => [{'a' => 1}, {'b' => 2}]})
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      expect(Uploader).to receive(:remote_upload).and_return({path: 'a/b/c/d'})
      s.data['full_set_revision'] = 'asdfjkl'
      s.detach_extra_data('force')
      expect(s.data['extra_data_private_path']).to eq('a/b/c/d')
    end

    it 'should upload if no extra_data_nonce defined and data too big' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(1).times.and_return(nil)
      s.detach_extra_data(true)
      expect(paths).to eq(['private'])
    end

    it 'should upload if extra_data_nonce is already defined and the data has changed' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u, data: {'extra_data_nonce' => 'bacon', 'events' => [{}, {}]})
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.and_return(nil)
      s.detach_extra_data(true)
      expect(paths).to eq(['private'])
    end

    it 'should upload if forced to' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(1).times.and_return(nil)
      s.detach_extra_data('force')
      expect(paths).to eq(['private'])   
    end

    it 'should upload a public data version as well if available' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      s.data['events'] = [
        {'id' => 1, 'secret' => true},
        {'id' => 2, 'passowrd' => '12345'},
        {'id' => 3},
        {'id' => 4},
      ]
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
          json = JSON.parse(File.read(local))
          expect(json).to eq([
            {"id"=>1, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>2, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>3, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>4, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
          ])
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(1).times.and_return(nil)
      s.detach_extra_data('force')
      expect(paths).to eq(['private'])   
    end

    it 'should clear the data attribute when uploading remote version' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      s.data['events'] = [
        {'id' => 1, 'secret' => true},
        {'id' => 2, 'passowrd' => '12345'},
        {'id' => 3},
        {'id' => 4},
      ]
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(1).times.and_return(nil)
      s.detach_extra_data('force')
      expect(paths).to eq(['private']) 
      expect(s.data['events']).to eq(nil)
      expect(s.data['extra_data_nonce']).to_not eq(nil)
    end

    it "should schedule future upload if upload attempt gets throttled" do
      u = User.create
      b = Board.create(user: u)
      b.process({'buttons' => [{'id' => 1, 'label' => 'cat'}]})
      Worker.process_queues
      BoardDownstreamButtonSet.last_scheduled_stamp = nil
      bs = BoardDownstreamButtonSet.update_for(b.global_id, true)
      expect(bs).to_not eq(nil)
      expect(bs).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.and_raise("throttled upload")
      expect(RemoteAction.count).to eq(0)
      bs.detach_extra_data(true)
      expect(RemoteAction.count).to eq(1)
      ra = RemoteAction.last
      expect(ra.path).to eq("#{b.global_id}")
      expect(ra.action).to eq("upload_button_set")
      expect(ra.act_at).to be > 4.minutes.from_now
      expect(paths).to eq([])    
    end

    it "should skip upload attempt if a future one is already scheduled" do
      u = User.create
      b = Board.create(user: u)
      b.process({'buttons' => [{'id' => 1, 'label' => 'cat'}]})
      Worker.process_queues
      BoardDownstreamButtonSet.last_scheduled_stamp = nil
      bs = BoardDownstreamButtonSet.update_for(b.global_id, true)
      expect(bs).to_not eq(nil)
      expect(bs).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to_not receive(:remote_upload)
      expect(RemoteAction.count).to eq(0)
      ra = RemoteAction.create(path: b.global_id, act_at: 30.seconds.from_now, action: 'upload_button_set')
      bs.detach_extra_data(true)
      expect(RemoteAction.count).to eq(1)
      expect(paths).to eq([])    
    end
  end

  describe "extra_data_attribute" do
    it 'should return the correct value' do
      expect(LogSession.new.extra_data_attribute).to eq('events')
      expect(BoardDownstreamButtonSet.new.extra_data_attribute).to eq('buttons')
    end
  end

  describe "skip_extra_data_processing?" do
    it 'should return the correct value' do
      s = LogSession.new
      expect(s.skip_extra_data_processing?).to eq(false)
      s.data = {}
      expect(s.skip_extra_data_processing?).to eq(false)
      s.data['extra_data_nonce'] = 'asdf'
      expect(s.skip_extra_data_processing?).to eq(true)
      s.data['extra_data_nonce'] = nil
      expect(s.skip_extra_data_processing?).to eq(false)
      s.instance_variable_set('@skip_extra_data_update', true)
      expect(s.skip_extra_data_processing?).to eq(true)
    end
  end

  describe "extra_data_too_big?" do
    it 'should return the correct value' do
      s = LogSession.new
      expect(s.extra_data_too_big?).to eq(false)
      list = [{}] * 100
      s.data = {'events' => list}
      expect(s.extra_data_too_big?).to eq(false)
    end
  end

  describe "assert_extra_data" do
    it 'should do nothing with no url provided' do
      expect(Typhoeus).to_not receive(:get)
      s = LogSession.new
      s.assert_extra_data
      s.data = {}
      s.assert_extra_data
    end

    it 'should apply the remote request results if a url is available' do
      s = LogSession.new(data: {'extra_data_nonce' => 'asdfasdf'})
      expect(s.extra_data_private_url).to_not eq(nil)
      expect(Typhoeus).to receive(:get).with(s.extra_data_private_url, {timeout: 10}).and_return(OpenStruct.new(body: [{a: 1}].to_json))
      s.assert_extra_data
      expect(s.data['events']).to eq([{'a' => 1}])
    end
  end

  describe "clear_extra_data" do
    it 'should schedule clearing if a nonce is set' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(data: {'extra_data_nonce' => 'whatever'}, user: u, author: u, device: d)

      paths = LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s, s.data['extra_data_version'] || 0)
      s.clear_extra_data
      expect(Worker.scheduled?(LogSession, :perform_action, {'method' => 'clear_extra_data', 'arguments' => [s.global_id, paths]})).to eq(true)
    end

    it 'should not schedule clearing if no nonce is set' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(data: {'extra_data_nonce' => nil}, user: u, author: u, device: d)
      s.clear_extra_data
      expect(Worker.scheduled?(LogSession, :perform_action, {'method' => 'clear_extra_data', 'arguments' => ['whatever', s.global_id]})).to eq(false)
    end

    it 'should clear public and private URLs' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create!(user: u, author: u, device: d, data: {})
      expect(LogSession).to_not receive(:extra_data_remote_paths)
      expect(Uploader).to receive(:remote_remove).with('a')
      expect(Uploader).to receive(:remote_remove).with('b')
      LogSession.clear_extra_data(s.global_id, ['a', 'b'])
    end
  end

  describe "extra_data_remote_paths" do
    it 'should return the correct paths' do
      private_key = GoSecure.hmac('nonce', 'extra_data_private_key', 1)
      obj = OpenStruct.new(global_id: 'global_id', data: {})
      expect(LogSession.extra_data_remote_paths('nonce', obj)).to eq(
        [
          "extrasnonce/LogSession/global_id/nonce/data-#{private_key}.json",
          "extrasnonce/LogSession/global_id/nonce/data-global_id.json"
        ]
      )
      expect(LogSession.extra_data_remote_paths('nonce', obj, 0)).to eq(
        [
          "/extrasn/LogSession/global_id/nonce/data-#{private_key}.json",
          "/extrasn/LogSession/global_id/nonce/data-global_id.json"
        ]
      )
    end
  end

  describe "clear_extra_data_orphans" do
    it 'should have specs' do
      # TODO
    end
  end
end
