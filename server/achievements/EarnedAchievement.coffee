mongoose = require 'mongoose'
jsonschema = require '../../app/schemas/models/earned_achievement'
util = require '../../app/core/utils'
log = require 'winston'

EarnedAchievementSchema = new mongoose.Schema({
  notified:
    type: Boolean
    default: false
}, {strict:false})

EarnedAchievementSchema.pre 'save', (next) ->
  @set('changed', Date.now())
  next()

EarnedAchievementSchema.index({user: 1, achievement: 1}, {unique: true, name: 'earned achievement index'})
EarnedAchievementSchema.index({user: 1, changed: -1}, {name: 'latest '})

EarnedAchievementSchema.statics.createForAchievement = (achievement, doc, originalDocObj, done) ->
  User = require '../users/User'
  userObjectID = doc.get(achievement.get('userField'))
  userID = if _.isObject userObjectID then userObjectID.toHexString() else userObjectID # Standardize! Use strings, not ObjectId's

  earned =
    user: userID
    achievement: achievement._id.toHexString()
    achievementName: achievement.get 'name'
    earnedRewards: achievement.get 'rewards'

  pointWorth = achievement.get('worth') ? 10
  gemWorth = achievement.get('rewards')?.gems ? 0
  earnedPoints = 0
  earnedGems = 0
  
  wrapUp = (earnedAchievementDoc) ->
    # Update user's experience points
    update = {$inc: {points: earnedPoints, 'earned.gems': earnedGems}}
    for rewardType, rewards of achievement.get('rewards') ? {}
      continue if rewardType is 'gems'
      if rewards.length
        update.$addToSet ?= {}
        update.$addToSet["earned.#{rewardType}"] = $each: rewards
    User.update {_id: mongoose.Types.ObjectId(userID)}, update, {}, (err, count) ->
      log.error err if err?
      done?(earnedAchievementDoc)

  isRepeatable = achievement.get('proportionalTo')?
  if isRepeatable
    #log.debug 'Upserting repeatable achievement called \'' + (achievement.get 'name') + '\' for ' + userID
    proportionalTo = achievement.get 'proportionalTo'
    originalAmount = if originalDocObj then util.getByPath(originalDocObj, proportionalTo) or 0 else 0
    docObj = doc.toObject()
    newAmount = docObj[proportionalTo]

    if originalAmount isnt newAmount
      expFunction = achievement.getExpFunction()
      earned.notified = false
      earned.achievedAmount = newAmount
      earnedPoints = earned.earnedPoints = (expFunction(newAmount) - expFunction(originalAmount)) * pointWorth
      earnedGems = earned.earnedGems = (expFunction(newAmount) - expFunction(originalAmount)) * gemWorth
      earned.previouslyAchievedAmount = originalAmount
      EarnedAchievement.update {achievement: earned.achievement, user: earned.user}, earned, {upsert: true}, (err) ->
        return log.debug err if err?

      #log.debug earnedPoints
      wrapUp(new EarnedAchievement(earned))
    else
      done?()

  else # not alreadyAchieved
    #log.debug 'Creating a new earned achievement called \'' + (achievement.get 'name') + '\' for ' + userID
    earned.earnedPoints = pointWorth
    earned.earnedGems = gemWorth
    (new EarnedAchievement(earned)).save (err, doc) ->
      return log.error err if err?
      earnedPoints = pointWorth
      earnedGems = gemWorth
      wrapUp(doc)

  User.saveActiveUser userID, "achievement"

module.exports = EarnedAchievement = mongoose.model('EarnedAchievement', EarnedAchievementSchema)
