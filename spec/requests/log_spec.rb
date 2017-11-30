require 'spec_helper'

describe App, type: :request do
  let(:log_file) { File.join(App.root, 'log', "deploy-#{no}.log") }
  let(:no) { '123' }

  before { `touch #{log_file}` }

  it 'log?live=1' do
    get '/log', live: 1, no: no
    expect(last_response).to be_ok
  end

  it 'log' do
    get '/log', no: no
    expect(last_response).to be_ok
  end

  it 'log not exisst' do
    get '/log', no: 456
    expect(last_response).to be_ok
  end
end
