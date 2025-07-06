# mastodon_client.rb
require 'mastodon'
require 'uri'
require 'cgi'

module MastodonClient
  BASE_URL = ENV['MASTODON_BASE_URL']
  TOKEN = ENV['MASTODON_TOKEN']
  
  # 지연 초기화로 frozen string 문제 해결
  def self.client
    @client ||= Mastodon::REST::Client.new(base_url: BASE_URL, bearer_token: TOKEN)
  end
  
  def self.streamer
    @streamer ||= Mastodon::Streaming::Client.new(base_url: BASE_URL, bearer_token: TOKEN)
  end
  
  # 마스토돈 연결 확인용
  def self.test_connection
    begin
      account = client.verify_credentials
      puts "🔗 마스토돈 연결 성공!"
      puts "   계정: @#{account.acct} (#{account.display_name || account.username})"
      true
    rescue => e
      puts "💥 연결 실패: #{e.message}"
      false
    end
  end
  
  # 멘션 리스너 시작
  def self.listen_mentions(&block)
    streamer.user do |event|
      if event.is_a?(Mastodon::Notification) && event.type == 'mention'
        block.call(event)
      end
    end
  rescue => e
    puts "[오류] 멘션 수신 실패: #{e.message}"
    puts "        10초 후 재시도..."
    sleep 10
    retry
  end
  
  # 특정 멘션에 답글 전송
  def self.reply(mention, message)
    acct = mention.account.acct
    status_id = mention.status.id
    reply_text = "@#{acct} #{message}"
    begin
      client.create_status(reply_text, in_reply_to_id: status_id, visibility: 'public')
      puts "✅ @#{acct} 에게 답글 전송 완료"
    rescue => e
      puts "❌ 답글 전송 실패: #{e.message}"
    end
  end
  
  # 일반 툿 전송
  def self.post_status(message, visibility: 'public')
    begin
      client.create_status(message, visibility: visibility)
      puts "📤 툿 전송 완료"
    rescue => e
      puts "❌ 툿 전송 실패: #{e.message}"
    end
  end
end
