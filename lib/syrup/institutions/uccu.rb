require 'date'

# Net::HTTP::Persistent::Error: too many connection resets (due to An established connection was aborted by the software i
# n your host machine. - Errno::ECONNABORTED) after 2 requests on 24106116
        #from C:/Ruby192/lib/ruby/gems/1.9.1/gems/net-http-persistent-1.8/lib/net/http/persistent.rb:446:in `rescue in re
#quest'
        #from C:/Ruby192/lib/ruby/gems/1.9.1/gems/net-http-persistent-1.8/lib/net/http/persistent.rb:422:in `request'
        #from C:/Ruby192/lib/ruby/gems/1.9.1/gems/mechanize-2.0.1/lib/mechanize/http/agent.rb:204:in `fetch'
        #from C:/Ruby192/lib/ruby/gems/1.9.1/gems/mechanize-2.0.1/lib/mechanize.rb:539:in `request_with_entity'
        #from C:/Ruby192/lib/ruby/gems/1.9.1/gems/mechanize-2.0.1/lib/mechanize.rb:485:in `post'
        #from (irb):16
        #from C:/Ruby192/bin/irb:12:in `<main>'

module Syrup
  module Institutions
    class Uccu < InstitutionBase
      
      class << self
        def name
          "UCCU"
        end
        
        def id
          "uccu"
        end
      end
      
      def fetch_account(account_id)
        fetch_accounts
      end
      
      def fetch_accounts
        ensure_authenticated

        # List accounts
        page = agent.post('https://pb.uccu.com/UCCU/Ajax/RpcHandler.ashx',
                          '{"id":0,"method":"accounts.getBalances","params":[false]}',
                          'X-JSON-RPC' => 'accounts.getBalances')
        
        json = MultiJson.decode(page.body)

        accounts = []
        json['result'].each do |account|
          next if account['accountIndex'] == -1
          
          new_account = Account.new(:id => account['accountIndex'])
          new_account.name = account['displayName'][/^[^(]*/, 0].strip
          new_account.account_number = account['displayName'][/\(([*0-9-]+)\)/, 1]
          new_account.current_balance = account['current'].to_f
          new_account.available_balance = account['available'].to_f
          # new_account.type = :deposit # :credit
          
          accounts << new_account
        end

        accounts
      end
      
      def fetch_transactions(account_id, starting_at, ending_at)
        ensure_authenticated
        
        transactions = []
        
        page = agent.get("https://pb.uccu.com/UCCU/Accounts/Activity.aspx?index=#{account_id}")
        form = page.form("MAINFORM")
        form.ddlAccounts = account_id
        form.ddlType = 0 # 0 = All types of transactions
        form.field_with(:id => 'txtFromDate_textBox').value = starting_at.month.to_s + starting_at.strftime('/%e/%Y')
        form.field_with(:id => 'txtToDate_textBox').value = ending_at.month.to_s + ending_at.strftime('/%e/%Y')
        submit_button = form.button_with(:name => 'btnSubmitHistoryRequest')
        page = form.submit(submit_button)
        
        # Look for the account balance
        account = find_account_by_id(account_id)
        page.search('.summaryTable tr').each do |row_element|
          first_cell_text = ''
          row_element.children.each do |cell_element|
            if first_cell_text.empty?
              first_cell_text = cell_element.content.strip if cell_element.respond_to? :name
            else
              case first_cell_text
              when "Available Balance:"
                account.available_balance = parse_currency(cell_element.content.strip)
              when "Current Balance:"
                account.current_balance = parse_currency(cell_element.content.strip)
              end
            end
          end
        end
        
        # Get all the transactions
        page.search('#ctlAccountActivityChecking tr').each do |row_element|
          next if row_element['class'] == 'header'
          
          data = row_element.css('td').map {|element| element.content.strip }
            
          transaction = Transaction.new
          transaction.posted_at = Date.strptime(data[0], '%m/%d/%Y')
          transaction.payee = data[3]
          transaction.status = :posted # :pending
          transaction.amount = -parse_currency(data[4]) if data[4].size > 1
          transaction.amount = parse_currency(data[5]) if data[5].size > 1

          transactions << transaction
        end
        
        transactions
      end
      
      private
      
      def ensure_authenticated
        
        # Check to see if already authenticated
        page = agent.get('https://pb.uccu.com/UCCU/Accounts/Activity.aspx')
        if page.body.include?("Please enter your User ID and Password below.") || page.body.include?("Your Online Banking session has expired.")
          
          raise InformationMissingError, "Please supply a username" unless self.username
          raise InformationMissingError, "Please supply a password" unless self.password
          
          @agent = Mechanize.new
          
          # Enter the username
          page = agent.get('https://pb.uccu.com/UCCU/Login.aspx')
          form = page.form('MAINFORM')
          form.field_with(:id => 'ctlSignon_txtUserID').value = username
          form.field_with(:id => 'ctlSignon_txtPassword').value = password
          form.field_with(:id => 'ctlSignon_ddlSignonDestination').value = 'Accounts.Overview'
          form.TestJavaScript = 'OK'
          login_button = form.button_with(:name => 'ctlSignon:btnLogin')
          page = form.submit(login_button)
          
          # If the supplied username/password is incorrect, raise an exception
          raise InformationMissingError, "Invalid username or password" if page.body.include?("Login not accepted.") || page.body.include?("Please enter a valid signon ID.") || page.body.include?("Please enter a valid Password.")

          # Secret questions???
          
          raise "Unknown URL reached. Try logging in manually through a browser." if page.uri.to_s != "https://pb.uccu.com/UCCU/Accounts/Overview.aspx"
        end
        
        true
      end
      
    end
  end
end