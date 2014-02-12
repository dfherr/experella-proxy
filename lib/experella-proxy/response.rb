module ExperellaProxy
  #
  # Response is used to store incoming (HTTP) responses and parsed data
  #
  # Every Response belongs to a request {Request}
  #
  class Response

    include ExperellaProxy::Globals

    attr_reader :header

    # The constructor
    #
    # @param request [Request] Request the response belongs to
    def initialize(request)
      @request = request
      @conn = request.conn
      @header = {}
      @status_code = 500
      @chunked = false # if true the parsed body will be chunked
      @buffer = false # default is false, so incoming data will be streamed,
      # used for http1.0 clients and transfer-encoding chunked backend responses
      @send_buffer = String.new
      @response_parser = Http::Parser.new
      init_http_parser
    end

    # Adds data to the response object
    #
    # data must be formatted as string
    #
    # On Http::Parser::Error parsing gets interrupted and the connection closed
    #
    # @param str [String] data as string
    def <<(str)
      begin
        @response_parser << str
      rescue Http::Parser::Error
        log.warn ["Parser error caused by invalid response data", "@#{@conn.signature}"]
        # on error unbind response_parser object, so additional data doesn't get parsed anymore
        #
        # assigning a string to the parser variable, will cause incoming data to get buffered
        # imho this is a better solution than adding a condition for this rare error case
        @response_parser = ""
        @conn.close
      end
    end

    # Returns the data in send_buffer and empties the send_buffer
    #
    # @return [String] data to send
    def flush
      log.debug [:data_to_user, @send_buffer]
      @send_buffer.slice!(0, @send_buffer.length)
    end

    # Returns if the send_buffer is flushed? (empty)
    #
    # @return [Boolean]
    def flushed?
      @send_buffer.empty?
    end

    # Reconstructs modified http response in send_buffer
    #
    # Reconstructed response must be a valid response according to the HTTP Protocol
    #
    # Header order is determined by {#header}.each
    #
    def reconstruct_header
      @send_buffer = ""
      #start line
      @send_buffer << "HTTP/1.1 "
      @send_buffer << @status_code.to_s + ' '
      @send_buffer << HTTP_STATUS_CODES[@status_code] + "\r\n"
      #header fields
      @header.each do |key, value|
        @send_buffer << key.to_s + ": "
        if value.is_a?(Array)
          @send_buffer << value.shift
          until value.empty? do
            @send_buffer << "," + value.shift
          end
        else
          @send_buffer << value
        end
        @send_buffer << "\r\n"
      end
      @send_buffer << "\r\n"
      #reconstruction complete
      log.debug [:response_reconstructed_header, @send_buffer]
    end

    # Adds a hash to {#header}
    #
    # symbolizes hsh keys, duplicate key values will be overwritten with hsh values
    #
    # @param hsh [Hash] hash with HTTP header Key:Value pairs
    def update_header(hsh)
      hsh = hsh.inject({}) { |memo, (k, v)| memo[k.to_sym] = v; memo }
      @header.update(hsh)
    end

    private

    # initializes the response http parser
    def init_http_parser
      #called when response headers are completely parsed (first \r\n\r\n triggers this)
      @response_parser.on_headers_complete = proc do |h|

        @status_code = @response_parser.status_code

        if @request.keep_alive
          @header[:Connection] = "Keep-Alive"
        end

        # handle the transfer-encoding
        #
        # if no transfer encoding and no content-length is given, terminate connection after backend unbind
        #
        # if no transfer encoding is given, but there is content-length, just keep the content-length and send the message
        #
        # if a transfer-encoding is given, continue with Transfer-Encoding chunked and remove false content-length
        # header if present. Old Transfer-Encoding header will be removed with all other hop-by-hop headers
        #
        if h["Transfer-Encoding"].nil?
          # if no transfer-encoding and no content-length is present, set Connection: close
          if h["Content-Length"].nil?
            @request.keep_alive = false
            @header[:Connection] = "close"
          end
        #chunked encoded
        else
          # buffer response data if client uses http 1.0 until message complete
          if @request.header[:http_version][0] == 1 && @request.header[:http_version][1] == 0
            @buffer = true
          else
            h.delete("Content-Length")
            @chunked = true unless @request.header[:http_method] == "HEAD"
            @header[:"Transfer-Encoding"] = "chunked"
          end
        end

        # remove all hop-by-hop header fields
        unless h["Connection"].nil?
          h["Connection"].each do |s|
            h.delete(s)
          end
        end
        HOP_HEADERS.each do |s|
          h.delete(s)
        end


        via = h.delete("Via")
        if via.nil?
          via = "1.1 experella"
        else
          via << "1.1 experella"
        end
        @header[:Via] = via


        update_header(h)
        unless @buffer
          # called before any data is put into send_buffer
          reconstruct_header
          @conn.send_data flush
        end
      end

      @response_parser.on_body = proc do |chunk|
        if @chunked
          # add hexadecimal chunk size
          @send_buffer << chunk.size.to_s(16)
          @send_buffer << "\r\n"
          @send_buffer << chunk
          @send_buffer << "\r\n"
        else
          @send_buffer << chunk
        end
        unless @buffer
          @conn.send_data flush
        end
      end

      @response_parser.on_message_complete = proc do
        if @chunked
          # send closing chunk
          @send_buffer << "0\r\n\r\n"
          @conn.send_data flush
        elsif @buffer
          @header[:"Content-Length"] = @send_buffer.size.to_s
          body = flush
          reconstruct_header
          @send_buffer << body
          @conn.send_data flush
        end
      end

    end
  end
end