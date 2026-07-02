class User < ApplicationRecord
  include Registration

  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy

  # :member is the baseline; :domain_admin is granted to the first user ever (via
  # the Setup flow) and administers the whole install.
  enum :role, { member: "member", domain_admin: "domain_admin" }, default: :member

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  # Generate a fresh single-use code and email its magic link. `for:` names the
  # intent at the call site (:sign_in / :sign_up); it's a Ruby keyword, so it's
  # read back through the binding. Returns the SignInCode record.
  def send_magic_link(for: :sign_in)
    purpose = binding.local_variable_get(:for)
    code, plaintext = SignInCode.generate_for(self)
    code.save!
    SessionMailer.magic_link(self, plaintext, purpose: purpose).deliver_later
    code
  end
end
