# bot/mastodon_client.rb
require 'mastodon'

module MastodonClient
  @last_mention_id = nil

  def self.client
    base_url = ENV['MASTODON_BASE_URL']
    token = ENV['MASTODON_TOKEN']

    unless base_url && token
      raise "환경변수 설정 누락: MASTODON_BASE_URL 또는 MASTODON_TOKEN이 없습니다."
    end

    @client ||= Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: token
    )
  end

  def self.listen_mentions
    begin
      options = {}
      options[:since_id] = @last_mention_id if @last_mention_id

      notifications = client.notifications(options)
      mentions = notifications.select { |n| n.type == 'mention' }

      if mentions.any?
        @last_mention_id = mentions.first.id
        puts "🟢 새로운 멘션 #{mentions.size}개 도착!"

        mentions.reverse_each do |mention|
          acct = mention.account.acct
          content = mention.status&.content.to_s.gsub(/<[^>]*>/, '').strip
          puts "   📬 @#{acct}: #{content}"

          yield mention if block_given?
        end
      else
        print '.'  # 대기 중 표시
      end

    rescue Mastodon::Error::TooManyRequests => e
      puts "⏳ API 요청 한도 초과: 60초 대기"
      sleep 60
    rescue Mastodon::Error::Unauthorized => e
      puts "🔒 인증 오류: 토큰을 확인하세요 - #{e.message}"
      sleep 30
    rescue Mastodon::Error::NotFound => e
      puts "🌐 서버 연결 실패: BASE_URL 확인 - #{e.message}"
      sleep 30
    rescue => e
      puts "❌ 멘션 수신 중 오류: #{e.message}"
      puts "   위치: #{e.backtrace.first}"
      sleep 30
    end
  end

  def self.reply(mention, message)
    acct = mention.account.acct
    status_id = mention.status&.id

    begin
      messages = split_long_message(message, acct)

      if messages.size == 1
        response = send_single_reply(acct, messages.first, status_id)
        puts "📨 @#{acct}에게 응답 완료"
        return response
      else
        responses = send_thread_replies(acct, messages, status_id)
        puts "📚 @#{acct}에게 스레드 응답 완료 (#{messages.size}개)"
        return responses
      end

    rescue Mastodon::Error::TooManyRequests => e
      puts "⚠️ 답글 전송 한도 초과: 60초 대기 후 재시도"
      sleep 60
      retry
    rescue Mastodon::Error::UnprocessableEntity => e
      puts "🚫 응답 실패 (형식 오류 또는 중복): #{e.message}"
      return nil
    rescue => e
      puts "🛑 답글 전송 실패: #{e.message}"
      puts "   대상: @#{acct rescue 'unknown'}"
      puts "   메시지 길이: #{message.length rescue 0}자"
      return nil
    end
  end

  def self.post_status(message, visibility: 'public')
    begin
      response = client.create_status(message, visibility: visibility)
      puts "✅ 상태 메시지 게시 완료"
      return response
    rescue => e
      puts "❌ 상태 메시지 게시 실패: #{e.message}"
      return nil
    end
  end

  def self.test_connection
    begin
      account = client.verify_credentials
      puts "🟢 마스토돈 서버 연결 성공"
      puts "   계정: @#{account.acct}"
      puts "   표시명: #{account.display_name}"
      puts "   팔로워: #{account.followers_count}명"
      return true
    rescue Mastodon::Error::Unauthorized => e
      puts "🔑 인증 실패: #{e.message}"
      return false
    rescue Mastodon::Error::NotFound => e
      puts "🌍 서버 주소 오류: #{e.message}"
      return false
    rescue => e
      puts "❌ 기타 연결 실패: #{e.message} (#{e.class})"
      return false
    end
  end

  def self.get_recent_mentions(limit: 10)
    begin
      notifications = client.notifications(limit: limit)
      mentions = notifications.select { |n| n.type == 'mention' }

      puts "📬 최근 멘션 #{mentions.size}개:"
      mentions.each_with_index do |mention, idx|
        acct = mention.account.acct
        content = mention.status&.content.to_s.gsub(/<[^>]*>/, '').strip
        puts "   #{idx + 1}. @#{acct}: #{content[0..50]}#{'...' if content.length > 50}"
      end

      return mentions
    rescue => e
      puts "❌ 최근 멘션 조회 실패: #{e.message}"
      return []
    end
  end

  private

  def self.split_long_message(message, acct)
    mention_prefix = "@#{acct} "
    max_length = 500
    available_length = max_length - mention_prefix.length

    return [message] if message.length <= available_length

    puts "✂️ 긴 메시지를 분할 중 (#{message.length}자)"

    messages = []
    remaining = message.dup

    while remaining.length > 0
      cut_point = find_good_cut_point(remaining, available_length - 10)
      cut_point = available_length - 10 if cut_point <= 0

      part = remaining[0...cut_point].strip
      remaining = remaining[cut_point..-1].to_s.strip

      messages << part
    end

    if messages.size > 1
      messages.map!.with_index do |msg, idx|
        "#{msg}\n\n(#{idx + 1}/#{messages.size})"
      end
    end

    messages
  end

  def self.find_good_cut_point(text, max_length)
    return text.length if text.length <= max_length

    [
      text.rindex("\n\n", max_length),
      text.rindex("\n", max_length),
      text.rindex(/[.?!。]/, max_length),
      text.rindex(" ", max_length),
    ].compact.max || 0
  end

  def self.send_single_reply(acct, message, reply_to_id)
    client.create_status(
      "@#{acct} #{message}",
      in_reply_to_id: reply_to_id,
      visibility: 'public'
    )
  end

  def self.send_thread_replies(acct, messages, reply_to_id)
    responses = []
    current_id = reply_to_id

    messages.each_with_index do |msg, idx|
      res = client.create_status(
        "@#{acct} #{msg}",
        in_reply_to_id: current_id,
        visibility: 'public'
      )
      responses << res
      current_id = res.id
      puts "   🔁 툿 #{idx + 1}/#{messages.size} 전송 완료"
      sleep 1 if idx < messages.size - 1
    end

    responses
  end
end
