class UserSerializer < ActiveModel::MongoidSerializer
  root false

  attributes :id, :guest, :name, :avatar, :tutorial_complete, :classification_count

  def id
    object._id.to_s
  end

  def classification_count
  	object.classifications.count
  end

=begin
  # PB: In the interest of speed, let's skip this until we actually need it
  def recent_subjects
    object.recents
  end
=end
end
