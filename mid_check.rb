require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

  gem "mechanize"
  gem "slack-ruby-client"
  gem "dotenv"
end

require "mechanize"
require "slack"
require "dotenv/load"

LOGIN_ID        = ENV["AMBI_LOGIN_ID"]
LOGIN_PW        = ENV["AMBI_LOGIN_PW"]
SLACK_API_TOKEN = ENV["AMBI_SLACK_API_TOKEN"]
SLACK_CHANNEL   = ENV["AMBI_SLACK_CHANNEL"]

LOGIN_URL         = "https://en-ambi.com/company_login/login/"
INTEREST_PAGE_URL = "https://mid-tenshoku.com/company/folder/"
ENTRY_URL         = "https://mid-tenshoku.com/company/entry/entry_list/"

Slack.configure do |config|
  config.token = SLACK_API_TOKEN
end

def users(nodes)
  nodes.map{|node|
    {
      jobname: node.search(".jobname")&.first&.text || node.search(".subject")&.first&.text,
      user: {
        login:   node.search(".status")&.first&.text&.strip,
        profile: node.search(".data.basic .prof")&.first&.text,
        name:    node.search(".data.user .userName")&.first&.text,
        id:      node.search(".data.basic .num")&.first&.text,
        company: {
          name: node.search(".data.user .companyData .name")&.first&.text&.strip,
          job:  node.search(".data.user .companyData .sub")&.first&.text&.strip,
        },
        experiences: {
          school:     node.search(".data.profile .school")&.first&.text,
          change_job: node.search(".data.profile .change")&.first&.text,
          past_jobs:  node.search(".data.profile .pastjob").map(&:text),
        }
      },
    }
  }
end

agent = Mechanize.new

page                  = agent.get(LOGIN_URL)
login_form            = page.form("frmLogin")
login_form.accLoginID = LOGIN_ID
login_form.accLoginPW = LOGIN_PW

# puts "--- LoginForm"
# pp login_form

page = agent.submit(login_form)
agent.get("https://en-ambi.com/company_login/auth/site_change")

page = agent.get(INTEREST_PAGE_URL)
puts "--- 興味ありページ"
profiles = page.search(".userSet")
puts "  件数: #{profiles.length}"
interests = users(profiles)
pp interests

page = agent.get(ENTRY_URL)

# 未対応に絞り込む
form = page.form("frm")
form.fields << Mechanize::Form::Field.new({"name" => "responce[]"}, 0)
page = agent.submit(form)

puts "--- エントリーページ"
profiles = page.search(".userSet")
puts "  件数: #{profiles.length}"
entries = users(profiles)
pp entries

client = Slack::Web::Client.new

def user_blocks(users)
  users.group_by{|x| x[:jobname] }.flat_map{|(title, rows)|
    [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: title,
          emoji: true
        }
      },
    ].concat(
      rows.map{|x|
        user = x[:user]
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: [
              user[:id],
              user[:name],
              "最終ログイン: #{user[:login]}",
              user[:profile],
              user.dig(:company, :name),
              user.dig(:company, :job),
              user.dig(:experiences, :past_jobs)&.join("\n"),
              user.dig(:experiences, :change_job),
              user.dig(:experiences, :school),
            ].compact.join("\n")
          }
        }
      }
    )
  }
end

client.chat_postMessage(
  channel: SLACK_CHANNEL,
  blocks: [
    {
      type: :header,
      text: {
        type: "plain_text",
        text: "ミドルの転職",
      },
    },
    {
      type: :section,
      text: {
        type: "plain_text",
        text: "🆕 本日の興味あり通信 🆕",
      },
    },
    {
      type: :section,
      text: {
        type: "plain_text",
        text: "興味あり: #{interests.length} 名",
      },
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "<#{INTEREST_PAGE_URL}|興味ありページはこちら>"
      }
    },
  ].concat(user_blocks(interests)),
  as_user: true,
)

client.chat_postMessage(
  channel: SLACK_CHANNEL,
  blocks: [
    {
      type: :header,
      text: {
        type: "plain_text",
        text: "ミドルの転職",
      },
    },
    {
      type: :section,
      text: {
        type: "plain_text",
        text: "🏄 本日のエントリー通信 🏄",
      },
    },
    {
      type: :section,
      text: {
        type: "plain_text",
        text: "エントリー: #{entries.length} 名",
      },
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "<#{ENTRY_URL}|エントリーはこちら>"
      }
    },
  ].concat(user_blocks(entries)),
  as_user: true,
)
