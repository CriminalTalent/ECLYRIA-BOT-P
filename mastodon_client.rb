# mastodon_client.rb

require 'mastodon'
require 'uri'
require 'json'

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url
    @client = Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: token
    )
    @streamer = Mastodon::Streaming::Client.new(
      base_url: base_url,
      bearer_token: token
    )
  end

  # 실시간 멘션 스트리밍 처리
  def stream_user(&block)
    puts "[마스토돈] 멘션 스트리밍 시작..."
    @streamer.user do |event|
      if event.is_a?(Mastodon::Notification) && event.type == 'mention'
        block.call(event)
      end
    end
  rescue => e
    puts "[에러] 스트리밍 중단됨: #{e.message}"
    sleep 5
    retry
  end

  # 멘션에 답글 작성
  def reply(to_acct, message)
    begin
      puts "[마스토돈] → @#{to_acct} 에게 응답 전송"
      @client.create_status(
        "@#{to_acct} #{message}",
        visibility: 'unlisted'
      )
    rescue => e
      puts "[에러] 응답 전송 실패: #{e.message}"
    end
  end

  # 전체 공지용 푸시 (ex. 아침 출석 알림 등)
  def broadcast(message)
    begin
      puts "[마스토돈] → 전체 공지 전송"
      @client.create_status(
        message,
        visibility: 'public'
      )
    rescue => e
      puts "[에러] 공지 전송 실패: #{e.message}"
    end
  end
end
