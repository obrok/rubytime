require 'spec_helper'

describe User do

  it "should generate password" do
    user = User.new
    user.password.should be_nil
    user.password_confirmation.should be_nil
    user.generate_password!
    user.password.should_not be_nil
    user.password_confirmation.should_not be_nil
  end

  it "should validate login format" do
    ["stefan)(*&^%$)", "foo bar", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "][;'/.,?><!@#}{}]"].each do |login|
      user = Employee.prepare :login => login
      user.should_not be_valid
      user.errors.on(:login).should_not be_nil
    end

    %w(maciej-lotkowski stefan_ks bob kiszka123 12foo123).each do |login|
      user = Employee.prepare :login => login
      user.should be_valid
    end
  end  
  
  it "should have a globally unique login" do
    Factory.create(:employee, {:login => 'foo'})
    Factory.build(:client_user, {:login => 'foo'}).should_not be_valid
  end

  it "shouldn't authenticate inactive user" do
    password = "awsumpass"
    login = "awsum-stefan"
    employee = Employee.prepare(
      :active => false,
      :login => login,
      :password => password,
      :password_confirmation => password
    )
    employee.save.should be_true
    User.authenticate(login, password).should be_nil
  end

  it "should authenticate user with ldap if basic auth fails" do
    Auth::LDAP.should_receive(:isLDAP?).and_return(true)
    Auth::LDAP.should_receive(:authenticate).and_return(true)

    password = "awsumpass"
    login = "SomeLogin"

    employee = Employee.prepare(
      :active => true,
      :login => login,
      :ldap_login => "ldap_login",
      :password => password,
      :password_confirmation => password
    )
    employee.save.should be_true
    User.authenticate("ldap_login", "ldap_password").should_not be_nil
  end

  it "should send welcome email to new user" do
    block_should(change(Merb::Mailer.deliveries, :size).by(1)) do
      Employee.generate
    end
    last_delivered_mail.text.should include("welcome")
  end

  it "should generate a password reset token with expiration time" do
    user = Employee.generate
    user.generate_password_reset_token.should be_true
    user.password_reset_token_exp.should <= DateTime.now + Rubytime::PASSWORD_RESET_LINK_EXP_TIME
  end

  it "should send email with password reset link to user requesting it" do
    user = Employee.generate
    block_should(change(Merb::Mailer.deliveries, :size).by(1)) do
      user.generate_password_reset_token
    end
    last_delivered_mail.text.should include("reset password")
  end

  it "should require password" do
    Employee.new.password_required?.should be_true

    user = Employee.generate
    user = Employee.get(user.id) # needs to be reloaded, to prevent from keeping password_confirmation set
    user.password_required?.should be_false
    user.password = "kiszka"
    user.password_required?.should be_true

    user = ClientUser.generate
    user.password_confirmation = "aaaaaa"
    user.password_required?.should be_true
  end

  it "shouldn't allow to delete it if there is a related invoice or activity" do
    user = Employee.generate
    Activity.generate :user => user
    block_should_not(change(User, :count)) do
      user.destroy
    end
  end

  # in april 2009 there were 22 working days (30 days total, but 8 on weekends)
  it "should properly calculate number of days without activities" do
    user = Employee.generate
    user.days_without_activities(date("2009-04-01"), date("2009-04-30")).should have(22).days

    Activity.prepare(:user => user, :date => date("2009-04-17")).save.should be_true
    Activity.prepare(:user => user, :date => date("2009-04-15")).save.should be_true

    user.days_without_activities(date("2009-04-01"), date("2009-04-30")).should have(20).days

    FreeDay.prepare(:user => user, :date => date("2009-04-21")).save.should be_true
    FreeDay.prepare(:user => user, :date => date("2009-04-22")).save.should be_true

    user.days_without_activities(date("2009-04-01"), date("2009-04-30")).should have(18).days
  end

  describe '#has_activities_on?' do
    before do
      @user = Employee.generate
      Activity.generate :user => @user, :date => date('2009-08-03')
    end

    it 'should return true for days with activities' do
      @user.has_activities_on?(date('2009-08-03')).should be_true
    end

    it 'should return false for days with no activities' do
      @user.has_activities_on?(date('2009-08-04')).should be_false
    end
  end

  describe "#can_manage_financial_data?" do
    context "for admin user" do
      before { @user = User.new :admin => true }
      it { @user.can_manage_financial_data?.should == true }
    end

    context "for non-admin user" do
      before { @user = User.new :admin => false }
      it { @user.can_manage_financial_data?.should == false }
    end
  end

  describe "with_activities" do
    before :all do
      @user = Employee.generate
    end

    it "should include users which have added activities" do
      Activity.generate :user => @user
      User.with_activities.should include(@user)
    end

    it "should not include users which haven't added any activities" do
      User.with_activities.should_not include(@user)
    end

    it "should not include duplicate entries" do
      2.times { Activity.generate :user => @user }
      User.with_activities.find_all { |u| u == @user }.length.should == 1
    end
  end

  describe "recent projects" do
    before :each do
      @user = Employee.generate
    end

    it "should retrieve RECENT_ACTIVITIES_NUM projects sorted by activity date" do
      projects = ['ani project', 'another project', 'project ani', 'not important'].map do |name|
        p = Project.generate(:name => name)
        p.users << @user
        p.save
        p
      end
      Activity.generate(:project => projects[0], :date => Date.today-2, :user => @user)
      Activity.generate(:project => projects[1], :date => Date.today-1, :user => @user)
      Activity.generate(:project => projects[2], :date => Date.today, :user => @user)
      Activity.generate(:project => projects[0], :date => Date.today+1, :user => @user)
      recent = @user.recent_projects
      recent.size.should == User::RECENT_ACTIVITIES_NUM
      recent.map(&:name).should == [projects[0].name, projects[2].name, projects[1].name]
    end
  end

  describe "with_activities_for_client" do
    before :each do
      @user = Employee.generate
      @project1 = Project.generate
      @project2 = Project.generate
      @client1 = @project1.client
    end

    it "should include users which have added activities for any of client's projects" do
      Activity.generate :user => @user, :project => @project1
      User.with_activities_for_client(@client1).should include(@user)
    end

    it "should not include users which haven't added any activities for any of client's projects" do
      Activity.generate :user => @user, :project => @project2
      User.with_activities_for_client(@client1).should_not include(@user)
    end

    it "should not include duplicate entries" do
      Activity.generate :user => @user, :project => @project1
      Activity.generate :user => @user, :project => @project1
      User.with_activities_for_client(@client1).should == [@user]
    end
  end
end

describe "admin" do
  it "should return a proper user_type" do
    Employee.new(:admin => true).user_type.should == :admin
  end
end

describe Employee do

  before :each do
    @user = Employee.generate
    @other = Employee.generate
    @admin = Employee.generate(:admin)
    @client_user = ClientUser.generate
    clear_mail_deliveries
  end

  it "should have calendar viewable by himself and admin" do
    @user.calendar_viewable?(@user).should be_true
    @user.calendar_viewable?(@admin).should be_true
    @user.calendar_viewable?(@other).should be_false
  end

  it "should create user" do
    block_should(change(Employee, :count).by(1)) { Employee.prepare.save.should be_true }
  end

  it "should be an employee" do
    Employee.new.is_employee?.should be_true
  end

  it "shouldn't be admin" do
    Employee.new.is_admin?.should be_false 
  end

  it "should return a proper user_type" do
    Employee.new.user_type.should == :employee
  end

  it "shouldn't create user without name" do
    @user.name = nil
    @user.save.should be_false
    @user.errors.on(:name).should_not be_nil
  end  
  
  it "shouldn't have client_id set" do
    @user.client_id.should be_nil
  end

  it "should be editable by himself and admin" do
    @user.editable_by?(@user).should be_true
    @user.editable_by?(@admin).should be_true
    @user.editable_by?(@other).should be_false
    @user.editable_by?(@client_user).should be_false
  end

  it "should create user with given password and authenticate" do 
    pass = "kiszka123"
    login = "stefan13"

    user = Employee.prepare :login => login, :password => pass, :password_confirmation => pass
    user.save.should be_true
    User.authenticate(login, pass).should == User.get(user.id)
  end

  it "should return nil for authentication with bad login or password" do
    User.authenticate("bad-login", "bad-password").should be_nil
  end

  it "should be admin if marked as admin" do
    Employee.new(:admin => true).is_admin?.should be_true
  end

  it "should find managers" do
    manager_role = Role.first_or_generate :name => 'Project Manager'
    manager = Employee.generate :role => manager_role

    managers = Employee.managers.all
    managers.should include(manager)
    managers.should_not include(@user)
  end

  it "should check if user has any activities for a date" do
    Activity.generate(:user => @user, :date => date("2008-11-23"))
    @user.has_activities_on_day(date("2008-11-23")).should be_true
  end

  describe ".send_timesheet_naggers_for" do
    it "should send emails to employees that have no activities on given day" do
      day = date('2009-08-03')
      Activity.all.destroy!
      Activity.generate :user => @user, :date => day

      Employee.send_timesheet_naggers_for(day)

      emails = Merb::Mailer.deliveries.map(&:to).flatten
      emails.should_not include(@user.email)
      emails.should include(@other.email)
    end
  end

  describe ".send_timesheet_reporter_for" do
    it "should send email to given address with a list of the employees who have no activities on given day" do
      Activity.all.destroy!
      Activity.generate :user => @user, :date => date('2009-08-03')

      block_should(change(Merb::Mailer.deliveries, :size).by(1)) do
        Employee.send_timesheet_reporter_for(Date.parse('2009-08-03'))
      end

      message = last_delivered_mail.text
      message.should_not include(@user.name) 
      message.should include(@other.name)
    end
  end

  describe "#activities_by_dates_and_projects" do
    it "should return nested tables dates -> projects -> activities" do
      @proj1 = Project.generate :name => 'BBB'
      @proj2 = Project.generate :name => 'AAA'
      
      @activity1 = Activity.generate :user => @user, :project => @proj1, :date => date('2009-08-10')
      @activity2 = Activity.generate :user => @user, :project => @proj2, :date => date('2009-08-12')
      @activity3 = Activity.generate :user => @user, :project => @proj1, :date => date('2009-08-12')
      @activity4 = Activity.generate :user => @user, :project => @proj2, :date => date('2009-08-12')

      @user.activities_by_dates_and_projects(date('2009-08-10')..date('2009-08-12')).should == [
        [date('2009-08-10'), [
          [@proj1, [@activity1]]
        ]],
        [date('2009-08-11'), []],
        [date('2009-08-12'), [
          [@proj2, [@activity2, @activity4]],
          [@proj1, [@activity3]]
        ]]
      ]
    end
  end

  describe "#send_timesheet_summary_for" do
    it "should create UserMailer and dispatch and deliver the message" do
      @date_range = date('2009-08-10')..date('2009-08-12')
      @activities_by_dates_and_projects = mock('activities_by_dates_and_projects')
      @user.stub! :activities_by_dates_and_projects => @activities_by_dates_and_projects

      @user_mailer = mock('UserMailer')
      @user_mailer.should_receive(:dispatch_and_deliver).with(:timesheet_summary,
        :to => @user.email,
        :from => Rubytime::CONFIG[:mail_from],
        :subject => "RubyTime timesheet summary for #{@date_range}"
      )
      UserMailer.should_receive(:new).with(
        :user => @user,
        :dates_range => @date_range,
        :activities_by_dates_and_projects => @activities_by_dates_and_projects
      ).and_return(@user_mailer)

      @user.send_timesheet_summary_for(@date_range)
    end
  end

  describe "#can_manage_financial_data?" do

    context "for admin user" do
      before { @employee = Employee.new :admin => true }
      it { @employee.can_manage_financial_data?.should == true }
    end

    context "for non-admin user" do
      before { @employee = Employee.new :admin => false }

      context "that has role that can manage financial data" do
        before { @employee.role = Role.new(:can_manage_financial_data => true) }
        it { @employee.can_manage_financial_data?.should == true }
      end

      context "that has role that cannot manage financial data" do
        before { @employee.role = Role.new(:can_manage_financial_data => false) }
        it { @employee.can_manage_financial_data?.should == false }
      end
    end
  end

  describe "saving user versions" do

    before :each do
      @employee = Employee.generate
      @master = Role.generate :name => 'Jedi Master'
    end

    it "should save user version on demand" do
      @employee.login = 'asdasd'
      version = @employee.save_new_version
      version.login.should == 'asdasd'
      version.id.should == @employee.id
      version.modified_at.should > DateTime.now - 60
      version.modified_at.should <= DateTime.now
    end

    it "should create a first version for the user" do
      @employee.versions.destroy!
      version = @employee.save_first_version
      version.id.should == @employee.id
      version.modified_at.should == @employee.created_at
    end

    it "should save user version on create" do
      @employee.versions.should have(1).record
    end

    it "should save user version on update, if role is changed" do
      block_should(change(UserVersion, :count).by(1)) do
        @employee.update(:role => @master)
      end
      @employee.reload
      @employee.versions[0].role.should_not == @master
      @employee.versions[1].role.should == @master
      @employee.versions[1].modified_at.should > DateTime.now - 60
      @employee.versions[1].modified_at.should <= DateTime.now
    end

    it "should not save user version on update, if role is not changed" do
      block_should_not(change(UserVersion, :count)) do
        @employee.update(:name => 'new name')
      end
    end

    it "should create a first version if it doesn't exist before saving a new one on update" do
      @employee.versions.destroy!
      @employee.versions.should have(0).records
      @employee.update :role => @master
      @employee.reload
      @employee.versions.should have(2).records
      @employee.versions[0].role.should_not == @master
      @employee.versions[1].role.should == @master
    end

    it "should create a first version correctly if not versioned attributes were modified" do
      lambda {
        @employee.versions.destroy!
        @employee.update :remember_me_token => 'rememberme', :active => !@employee.active?
      }.should_not raise_error
    end

    it "should delete user's version after his account is deleted" do
      @employee.update :role => @master
      block_should(change(UserVersion, :count).by(-2)) do
        @employee.destroy
      end
    end
  end

  describe "finding user versions" do

    before :each do
      @employee = Employee.generate
      @captain = Role.generate :name => 'Captain'
      @major   = Role.generate :name => 'Major'
      @general = Role.generate :name => 'General'
    end

    it "should return a correct version for the given day" do
      time_travel_to(2.days.from_now) { @employee.update :role => @captain }
      time_travel_to(5.days.from_now) { @employee.update :role => @major }
      time_travel_to(10.days.from_now) { @employee.update :role => @general }
      @employee.reload
      @employee.version(7.days.from_now).role.should == @major
    end

    it "should return the last version on that day" do
      now = Time.now
      night = now - now.hour.hours
      time_travel_to(night + 2.days + 14.hours) { @employee.update :role => @captain }
      time_travel_to(night + 2.days + 22.hours) { @employee.update :role => @major }
      time_travel_to(night + 3.days) { @employee.update :role => @general }
      @employee.reload
      @employee.version(2.days.from_now).role.should == @major
    end

    it "should return first user version if no version matches" do
      original_role = @employee.role
      time_travel_to(2.days.from_now) { @employee.update :name => @captain }
      time_travel_to(5.days.from_now) { @employee.update :name => @major }
      @employee.reload
      @employee.version(10.days.ago).role.should == original_role
    end

    it "should create a first version if no version is found at all" do
      @employee.update :name => 'Johnny'
      @employee.versions.destroy!
      @employee.reload
      time_travel_to(2.days.from_now) do
        version = @employee.version(Date.today)
        version.should_not be_nil
        version.id.should == @employee.id
        version.name.should == 'Johnny'
        version.modified_at.should == @employee.created_at
      end
    end

  end

end


describe ClientUser do

  it "shouldn't be admin" do
    ClientUser.new.is_admin?.should be_false 
  end

  it "shouldn't be an employee" do
    ClientUser.prepare.is_employee?.should be_false
  end

  it "should have client" do
    client_user = ClientUser.prepare :client => nil
    client_user.save.should be_false
    client_user.errors.on(:client).should_not be_nil
  end

  it "should return a proper user_type" do
    ClientUser.new.user_type.should == :client_user
  end  
  
  it "shouldn't have role_id set" do
    ClientUser.new.role_id.should be_nil
  end

end
