# /root/mastodon_bots/professor_bot/mastodon_client.rb
require 'mastodon'
require 'uri'
require 'json'
require 'dotenv'
require 'net/http'
Dotenv.load('.env')

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url
    @token = token
    @client = Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: token
    )
    @streamer = nil
  end

  # ================================
  # Mentions 감시용 API 호출 (폴링 방식)
  # ================================
  def fetch_mentions(since_id: nil)
    uri = URI("#{@base_url}/api/v1/notifications?types[]=mention")
    uri.query += "&since_id=#{since_id}" if since_id

    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{@token}"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    else
      puts "[HTTP 오류] #{res.code} #{res.message}"
      puts "응답 본문: #{res.body}"
      []
    end
  rescue => e
    puts "[에러] Mentions 불러오기 실패: #{e.message}"
    []
  end

  # ================================
  # 답글 / 공지 / DM
  # ================================
  def reply(acct, message, in_reply_to_id: nil)
    message = (message.to_s.empty?) ? "출석이 확인되었습니다." : message.dup
    status_text = "@#{acct} #{message}".dup
    puts "[마스토돈] → @#{acct} 에게 답글 전송"

    response = @client.create_status(
      status_text,
      in_reply_to_id: in_reply_to_id,
      visibility: 'unlisted'
    )
    puts "[응답 완료] #{message[0..50]}..."
    response
  rescue => e
    puts "[에러] 응답 전송 실패: #{e.message}"
    puts e.backtrace.first(3)
    nil
  end

  def broadcast(message)
    message = message.dup
    puts "[마스토돈] → 전체 공지 전송"
    @client.create_status(message, visibility: 'public')
  rescue => e
    puts "[에러] 공지 전송 실패: #{e.message}"
  end

  def say(message)
    message = message.dup
    puts "[마스토돈] → 일반 포스트 전송"
    @client.create_status(message, visibility: 'public')
  rescue => e
    puts "[에러] 포스트 전송 실패: #{e.message}"
  end

  def dm(to_acct, message)
    message = message.dup
    puts "[마스토돈] → @#{to_acct} DM 전송"
    status_text = "@#{to_acct} #{message}"
    @client.create_status(status_text, visibility: 'direct')
  rescue => e
    puts "[에러] DM 전송 실패: #{e.message}"
  end

  # ================================
  # 계정 확인
  # ================================
  def me
    @client.verify_credentials.acct
  rescue => e
    puts "[에러] 계정 확인 실패: #{e.message}"
    nil
  end

  # ================================
  # 환경변수 검사
  # ================================
  def self.validate_environment
    base_url = ENV['MASTODON_BASE_URL']
    token = ENV['MASTODON_TOKEN']

    missing_vars = []
    missing_vars << 'MASTODON_BASE_URL' if base_url.nil? || base_url.empty?
    missing_vars << 'MASTODON_TOKEN' if token.nil? || token.empty?

    if missing_vars.any?
      puts "필수 환경변수 누락: #{missing_vars.join(', ')}"
      puts ".env 파일을 확인해주세요."
      return false
    end
    true
  end

  # ================================
  # 싱글턴 인스턴스
  # ================================
  def self.client
    # 환경 변수 폴백 처리
    base_url = ENV['MASTODON_BASE_URL'] ||
                (ENV['MASTODON_DOMAIN'] && "https://#{ENV['MASTODON_DOMAIN']}")
  
    token = ENV['MASTODON_TOKEN'] || ENV['ACCESS_TOKEN']
  
    raise "MASTODON_BASE_URL/DOMAIN 누락" if base_url.nil? || base_url.empty?
    raise "MASTODON_TOKEN/ACCESS_TOKEN 누락" if token.nil? || token.empty?
  
    # 후행 슬래시 제거
    base_url = base_url.sub(%r{/\z}, '')
  
    puts "[DEBUG] MastodonClient 초기화 base_url=#{base_url.inspect}"
  
    @instance ||= new(base_url: base_url, token: token)
  end
end
