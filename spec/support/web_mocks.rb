module WebMocks
  def mock_requests!
    stub_request(:get, 'http://128.0.0.1:88/ping').to_return(status: 200, body: 'ok')
  end
end
