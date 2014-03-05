module Echo
  # Register custom middleware
  Faraday.register_middleware(:response,
                              :logging => Echo::ClientMiddleware::LoggingMiddleware,
                              :errors => Echo::ClientMiddleware::ErrorsMiddleware,
                              :echo10_datasets => Echo::ClientMiddleware::Echo10DatasetMiddleware,
                              :echo10_granules => Echo::ClientMiddleware::Echo10GranuleMiddleware)

  class Client
    include Echo::QueryTransformations

    CATALOG_URL="https://api.echo.nasa.gov"

    def self.get_datasets(options={}, token=nil)
      get('/catalog-rest/echo_catalog/datasets.json', options_to_item_query(options), token_header(token))
    end

    def self.get_dataset(id, options={}, token=nil)
      get("/catalog-rest/echo_catalog/datasets/#{id}.echo10", {}, token_header(token))
    end

    def self.get_granules(options={}, token=nil)
      options = options.dup
      format = options.delete(:format) || 'json'
      get("/catalog-rest/echo_catalog/granules.#{format}", options_to_granule_query(options), token_header(token))
    end

    def self.get_facets(options={}, token=nil)
      get("/catalog-rest/search_facet.json", options_to_facet_query(options), token_header(token))
    end

    def self.get_provider_holdings
      get("/catalog-rest/echo_catalog/provider_holdings.json")
    end

    def self.get_token_info(token)
      get("/echo-rest/tokens/#{token}/token_info.json", {}, token_header(token))
    end

    def self.get_data_quality_summary(catalog_item_id)
      response = get("/echo-rest/data_quality_summary_definitions", {'catalog_item_id' => catalog_item_id})
      references = response.body["references"]
      if references && references[0]
        get("/echo-rest/data_quality_summary_definitions/#{references[0]["id"]}")
      end
      # NCR 11014478 will allow this to be only one call to echo-rest
    end

    def self.get_token(username, password, client_id, ip)
      token = {
        token:
        {
          username: username,
          password: password,
          client_id: client_id,
          user_ip_address: ip
        }
      }
      Echo::Response.new(post("/echo-rest/tokens.json", token.to_json))
    end

    def self.username_recall(params)
      Rails.logger.info params.to_json
      post('/echo-rest/users/username_recall.json', params.to_json)
    end

    def self.password_reset(params)
      post('/echo-rest/users/password_reset.json', params.to_json)
    end

    def self.connection
      Thread.current[:edsc_echo_connection] ||= self.build_connection
    end

    private

    def self.token_header(token)
      token.present? ? {'Echo-Token' => token} : {}
    end

    def self.get(url, params={}, headers={})
      faraday_response = connection.get(url, params) do |req|
        headers.each do |header, value|
          req.headers[header] = value
        end
        Rails.logger.info req.headers.inspect
      end
      Echo::Response.new(faraday_response)
    end

    def self.post(url, body)
      faraday_response = connection.post(url) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = body if body
      end
      Echo::Response.new(faraday_response)
    end

    def self.build_connection
      Faraday.new(:url => CATALOG_URL) do |conn|
        conn.response :logging

        # The order of these handlers is important.  They are run last to first.
        # Our parsers depend on JSON / XML being converted to objects by earlier
        # parsers.
        conn.response :errors, :content_type => /\bjson$/
        conn.response :json, :content_type => /\bjson$/
        conn.response :echo10_granules, :content_type => "application/echo10+xml"
        conn.response :echo10_datasets, :content_type => "application/echo10+xml"
        conn.response :xml, :content_type => /\bxml$/

        conn.adapter  Faraday.default_adapter
      end
    end
  end
end
