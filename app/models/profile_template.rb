class ProfileTemplate < ApplicationRecord
  include GlobalId
  include Permissions
  include Processable

  include SecureSerialize
  protect_global_id
  belongs_to :user
  belongs_to :organization


  has_paper_trail :only => [:settings, :profile_id],
    :if => Proc.new{|b| PaperTrail.request.whodunnit && !PaperTrail.request.whodunnit.match(/^job/) }

  add_permissions('view', ['*']) { self.settings['public'] != false }
  add_permissions('view', 'edit', 'delete') {|user| self.user_id == user.id || (self.user && self.user.allows?(user, 'edit')) }
  add_permissions('view', 'edit') {|user| self.organization && self.organization.allows?(user, 'edit')}

  before_save :generate_defaults
  secure_serialize :settings

  def generate_defaults
    self.settings ||= {}
    self.settings['profile'] ||= {}
    self.settings['profile'].delete('results')
    self.settings['profile'].delete('encrypted_results')
    self.settings['public'] ||= false
    if self.settings['public'] == false
      self.public_profile_id = nil
    end
    self.communicator = self.settings['profile']['type'] == 'communicator'

    true
  end

  def nonce
    (self.settings || {})['nonce']
  end

  def nonce=(val)
    self.settings ||= {}
    self.settings['nonce'] = val
  end


  def self.static_templates(role)
    list = ['cpp']
    if role == 'communicator'
      list = ['cole']
    end
    list.map{|str| static_template(str) }.compact
  end

  def self.static_template(code)
    if code == 'cole'
      template = ProfileTemplate.new
      template.public_profile_id = code
      template.settings = {
        'public' => true,
        'profile' => {
          'name' => 'COLE - LCPS Continuum Of Language Expression',
          'description' => "The Interactive COLE, created by Chris Bugaj & Loudoun County Public Schools  - Communicators are scored based on 67 criteria in 11 different stages of communication. The COLE is quick to fill out and covers multiple levels of communication proficiency. Numerical summary scores are not useful for comparing across individuals, but can be helpful in tracking progress for a specific individual. Google Sheets version here, https://docs.google.com/spreadsheets/d/1HKXiq6IZN44dHLSBgkY2vuE-bu7FXTXiXOOQkwDzh_A/edit"
        }
      }
      return template
    elsif code == 'cpp'
      template = ProfileTemplate.new
      template.public_profile_id = code
      template.settings = {
        'public' => true,
        'profile' => {
          'name' => 'CPP - Communication Partner Profile',
          'description' => "Communication Partner Profile (CPPv1) AAC-Related Self-Reflection"
        }
      }
      return template
    elsif code == 'com-ff'
      template = ProfileTemplate.new
      template.public_profile_id = code
      template.settings = {
        'public' => true,
        'profile' => {
          'name' => 'ComFF - Communication Partner Profile',
          'description' => "COMFF Communication Partner Profile (CPPv1) AAC-Related Self-Reflection"
        }
      }
      return template
    elsif code == 'csicy'
      template = ProfileTemplate.new
      template.public_profile_id = code
      template.settings = {
        'public' => true,
        'profile' => {
          'name' => 'Communication Supports Inventory-Children and Youth (CSI-CY)',
          'description' => "The Communication Supports Inventory-Children and Youth (CSI-CY ) is a tool designed to make goal writing easier for teachers and speech-language pathologists who work with students who rely on augmentative and alternative communication (AAC) to communicate effectively. It is not an assessment, but a guide to organize your understanding of the impact of a student’s communication strengths and limitations on participation at school and at home. The idea is that you would use the CSI-CY to prepare for the IEP meeting by prioritizing areas that should be targeted in IEP goals related to communication."
        }
      }
      return template
    end
    return nil
  end

  def self.find_by_code(code)
    res = nil
    if code && !code.match(/^\d+_/)
      res = ProfileTemplate.find_by(public_profile_id: code)
      res = nil if res && res.settings['public'] == false
    end
    res ||= ProfileTemplate.find_by_global_id(code)
    res ||= ProfileTemplate.static_template(code)
    res
  end

  def process_params(params, non_user_params)
    self.settings ||= {}
    self.user ||= non_user_params[:user]
    self.organization = non_user_params[:organization] if non_user_params[:organization]
    self.settings['public'] = true if params['public'] == true || params['public'] == 'true'
    self.settings['public'] = false if params['public'] == false || params['public'] == 'false'
    self.settings['public'] = 'unlisted' if params['public'] == 'unlisted'
    self.settings['profile_id'] = params['profile_id']
    if params['profile_id'] != self.public_profile_id
      if self.settings['public'] == false
        self.public_profile_id = nil
      else
        prof = ProfileTemplate.find_by(public_profile_id: params['profile_id'])
        if !prof || (self.id && prof.id == self.id)
          self.public_profile_id = params['profile_id']
        else
          add_processing_error("profile_id \"#{params['profile_id']}\" already in use")
          return false
        end
      end
    end
    self.settings['profile'] = params['profile']
  end

  def self.default_profile_id(type)
    ENV["default_#{type}_profile_id".upcase]
  end
end
