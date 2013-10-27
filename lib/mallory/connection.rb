require 'eventmachine'
require 'em-http-request'
require 'redis'


module Mallory
  class Connection < EM::Connection
    def initialize(request_builder, proxy_builder, logger, certificate_manager)
      @logger = logger
      @request_builder = request_builder
      @proxy_builder = proxy_builder
      @certificate_manager = certificate_manager
      @start = Time.now
      @secure = false
      @proto = "http"
    end

    def ssl_handshake_completed # EM::Connection
      @logger.debug "Secure connection intercepted"
      @secure = true
    end

    def post_init # EM::Connection
      @logger.debug "Start connection"
    end

    def unbind(reason=nil) # EM::Connection
      @logger.debug "Close connection #{reason}"
    end

    def error
      @logger.info "Failure in #{Time.now-@start}s"
      send_data "HTTP/1.1 500 Internal Server Error\nContent-Type: text/html\nConnection: close\n\n"
      close_connection_after_writing
    end

    def receive_data(data) # EM::Connection
      begin
      request = @request_builder.build(data)
      rescue
        error
        return
      end
      if not @secure and request.method.eql?('connect')
        cc = @certificate_manager.get("localhost")
        private_key_file = Tempfile.new('private_key_file')
        print cc.key
        private_key_file.write (cc.key)
        private_key_file.close()
        send_data "HTTP/1.0 200 Connection established\r\n\r\n"
        start_tls :private_key_file => private_key_file.path, :cert_chain_file => './keys/ca.crt', :verify_peer => false
        return true
      end
      proxy = @proxy_builder.build
      proxy.callback {
        send_data proxy.response
        close_connection_after_writing
      }
      proxy.errback {
        error
      }
      request.protocol = 'https' if @secure
      proxy.perform(request)
    end
  end
end
