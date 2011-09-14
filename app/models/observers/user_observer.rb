class UserObserver
  include DataMapper::Observer

  observe User
  observe Employee

  before :save do
    self.version(DateTime.now) unless new?  # force creation of first version if it should exist but it doesn't

    # not using updated_at because of user versioning
    # for sake of simplicity we want this property to be called the same in User and UserVersion
    # if it was called updated_at, it would be overwritten when saving the UserVersion object
    self.modified_at = DateTime.now
    @role_changed = self.attribute_dirty?(:role_id)
  end

  after :save do
    save_new_version if self.versions.count == 0 || @role_changed
  end

  after :create do
    UserMailer.welcome(:user => self, :to => self.email, :from => Rubytime::CONFIG[:mail_from], :subject => "Welcome to Rubytime!").deliver
  end

  before :destroy do
    versions.all.destroy!
  end

  after :generate_password_reset_token do
    UserMailer.password_reset_link(:user => self, :to => self.email,
      :from => Rubytime::CONFIG[:mail_from], :subject => "Password reset request from Rubytime").deliver
  end
  
end
