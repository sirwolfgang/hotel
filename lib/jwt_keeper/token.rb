module JWTKeeper
  # This class acts as the main interface to wrap the concerns of JWTs. Handling everything from
  # encoding to invalidation.
  class Token
    attr_accessor :claims, :secret, :cookie_secret

    # Initalizes a new web token
    # @param options [Hash] the custom claims to encode
    # @param secret the secret to use during encoding, defaults to config
    # @param cookie_secret the cookie secret to use during encoding
    # @return [void]
    def initialize(options = {})
      @secret = options.delete(:secret) || JWTKeeper.configuration.secret
      @cookie_secret = options.delete(:cookie_secret)
      @claims = {
        nbf: DateTime.now.to_i, # not before
        iat: DateTime.now.to_i, # issued at
        jti: SecureRandom.uuid  # JWT ID
      }

      @claims.merge!(JWTKeeper.configuration.base_claims)
      @claims.merge!(options)
      @claims[:exp] = @claims[:exp].to_i if @claims[:exp].is_a?(Time)
    end

    # Creates a new web token
    # @param options [Hash] the custom claims to encode
    # @param secret the secret to use during encoding, defaults to config
    # @return [Token] token object
    def self.create(options)
      cookie_secret = SecureRandom.hex(16) if JWTKeeper.configuration.cookie_lock
      new(options.merge(cookie_secret: cookie_secret))
    end

    # Decodes and validates an existing token
    # @param raw_token [String] the raw token
    # @param cookie_secret [String] the cookie secret
    # @return [Token] token object
    def self.find(raw_token, secret: nil, cookie_secret: nil, iss: nil)
      claims = decode(raw_token, secret: secret, cookie_secret: cookie_secret, iss: iss)
      return nil if claims.nil?

      new_token = new(secret: secret, cookie_secret: cookie_secret, iss: iss)
      new_token.claims = claims

      return nil if new_token.revoked?
      new_token
    end

    # Sets a token to the pending rotation state. The expire is set to the maxium possible time but
    # is inherently ignored by the token's exp check and then rewritten with the revokation on
    # rotate.
    # @param token_jti [String] the token unique id
    # @return [void]
    def self.rotate(token_jti)
      Datastore.rotate(token_jti, JWTKeeper.configuration.expiry.from_now.to_i)
    end

    # Revokes a web token
    # @param token_jti [String] the token unique id
    # @return [void]
    def self.revoke(token_jti)
      Datastore.revoke(token_jti, JWTKeeper.configuration.expiry.from_now.to_i)
    end

    # Checks if a web token has been revoked
    # @return [Boolean]
    def self.revoked?(token_jti)
      Datastore.revoked?(token_jti)
    end

    # Easy interface for using the token's id
    # @return [String] token's uuid
    def id
      claims[:jti]
    end

    # Revokes and creates a new web token
    # @param new_claims [Hash] Used to override and update claims during rotation
    # @return [Token]
    def rotate(new_claims = nil)
      return self if claims[:iss] != JWTKeeper.configuration.issuer
      revoke

      new_claims ||= claims.except(:iss, :aud, :exp, :nbf, :iat, :jti)
      new_token = self.class.create(new_claims)

      @claims = new_token.claims
      @cookie_secret = new_token.cookie_secret
      self
    end

    # Revokes a web token
    # @return [void]
    def revoke
      return if invalid?
      Datastore.revoke(id, claims[:exp] - DateTime.now.to_i)
    end

    # Checks if a web token is pending a rotation
    # @return [Boolean]
    def pending?
      Datastore.pending?(id)
    end

    # Checks if a web token is pending a global rotation
    # @return [Boolean]
    def version_mismatch?
      claims[:ver] != JWTKeeper.configuration.version
    end

    # Checks if a web token has been revoked
    # @return [Boolean]
    def revoked?
      Datastore.revoked?(id)
    end

    # Checks if the token valid?
    # @return [Boolean]
    def valid?
      !invalid?
    end

    # Checks if the token invalid?
    # @return [Boolean]
    def invalid?
      self.class.decode(
        encode,
        secret: secret,
        cookie_secret: cookie_secret
      ).nil? || revoked?
    end

    # Encodes the jwt
    # @return [String] the encoded jwt
    def to_jwt
      encode
    end
    alias to_s to_jwt

    # Encodes the cookie
    # @return [Hash] the cookie options
    def to_cookie
      {
        value: cookie_secret,
        expires: Time.at(claims[:exp])
      }.merge(JWTKeeper.configuration.cookie_options)
    end

    # @!visibility private
    def self.decode(raw_token, secret: nil, cookie_secret: nil, iss: nil)
      secret ||= JWTKeeper.configuration.secret
      iss ||= JWTKeeper.configuration.issuer

      JWT.decode(raw_token, secret.to_s + cookie_secret.to_s, true,
                 algorithm: JWTKeeper.configuration.algorithm,
                 verify_iss: true,
                 verify_aud: true,
                 verify_iat: true,
                 verify_sub: false,
                 verify_jti: false,
                 leeway: 0,
                 iss: iss,
                 aud: JWTKeeper.configuration.audience
                ).first.symbolize_keys

    rescue JWT::DecodeError
      return nil
    end

    private

    # @!visibility private
    def encode
      JWT.encode(claims.compact,
                 secret.to_s + cookie_secret.to_s,
                 JWTKeeper.configuration.algorithm
                )
    end
  end
end
