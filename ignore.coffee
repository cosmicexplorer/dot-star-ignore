fs = require 'fs'
path = require 'path'

lo = require 'lodash'
async = require 'async'

negateRegex = /^!/g
nonRecursiveRegex = /^!?\//g
negateOrNonRecursiveRegex = /^(!|\/)\/?/g
commentRegex = /^#/g
directoryRegex = /\/$/g
nonSpaceRegex = /[^\s]/g

getIsntDirectoryWaterfall = (f, fcb, negate) ->
  async.waterfall [
    (wcb) -> fs.stat f, wcb
    (stats, wcb) ->
      res = stats.isDirectory()
      wcb null, (if negate then res else not res)],
    (err, res) -> if err then fcb no else fcb res

class IgnoreFile
  constructor: (@name, @precedence) ->
  matches: (files, cb) ->
    matches = files.filter (f) => (path.basename f) is @name
    async.filter matches,
      # directories can't be ignore files
      getIsntDirectoryWaterfall,
      (res) => cb null, res.map (file) => {file, ignoreFileObj: @}
  toIgnorePatterns: (dir, contents) ->
    contents.split('\n').map((line) -> line.trim())
      .filter((line) -> not line.match commentRegex)
      .filter((line) -> line.match nonSpaceRegex)
      .map (line) => new IgnorePattern
        pattern: line.replace(negateOrNonRecursiveRegex, "").replace(
          directoryRegex, "")
        precedence: @precedence
        negated: if (line.match negateRegex) then yes else no
        dir: dir
        recursive: (not line.match nonRecursiveRegex)
        needsDirectory: if (line.match directoryRegex) then yes else no

regexFromIgnore = (pattern, flags) ->
  new RegExp ('^' + pattern.split('').map((c) -> switch c
    when '*' then '.*'
    when '[', ']' then c
    else lo.escapeRegExp c).join('') + '$'), flags

fileDeeperThanDir = (file, dir) ->
  (path.dirname path.relative dir, file) isnt '.'

class IgnorePattern
  constructor: ({@pattern, @precedence, @negated, @dir, @recursive,
    @needsDirectory}) ->
    @reg = regexFromIgnore (path.join @dir, @pattern), 'g'
  matches: (file, cb) -> switch
    when not file.match @reg then cb no
    when (fileDeeperThanDir file, @dir) and not @recursive then cb no
    when @needsDirectory then getIsntDirectoryWaterfall file, cb, yes
    else cb yes

defaultIgnoreFiles = [new IgnoreFile '.gitignore', 0]
defaultPatterns = (dir) -> [new IgnorePattern
  pattern: '.git'
  precedence: 0
  negated: no
  dir: dir
  recursive: no
  needsDirectory: yes]

getNewIgnoreFiles = (dir, ignoreFileObjs) -> (files, cb) ->
  files = files.map (f) -> path.join dir, f
  async.map ignoreFileObjs,
    ((ignoreFile, mcb) ->
      ignoreFile.matches files, mcb),
    (err, res) -> cb err, files, lo.flatten res

getNewPatterns = (dir) -> (files, ignoreFilesFromDir, cb) ->
  newIgnoreFiles = lo.uniq ignoreFilesFromDir, no, 'file'
  async.map newIgnoreFiles, (({file, ignoreFileObj}, mcb) ->
    fs.readFile file, (err, res) -> if err then mcb err
    else
      pats = ignoreFileObj.toIgnorePatterns dir, res.toString()
      mcb null, pats),
    (err, res) -> cb err, files, lo.flatten res

getMaxOfProp = (prop, arr) ->
  max = -Infinity
  for el in arr
    if el[prop] > max then max = el[prop]
  max

applyPatterns = (invert) -> (files, patterns, cb) -> async.filter files,
  ((file, fcb) -> async.filter patterns,
    ((pat, fcb2) -> pat.matches file, fcb2),
    (pats) ->
      if pats.length is 0 then fcb yes
      else
        max = getMaxOfProp 'precedence', pats
        patsOfHighestPrecedence = pats.filter (p) -> p.precedence is max
        fcb invert isnt (lo.last patsOfHighestPrecedence).negated),
  (results) -> cb null, patterns, results

splitFilesDirectories = (patterns, nextFiles, cb) ->
  async.filter nextFiles,
    ((f, fcb) -> getIsntDirectoryWaterfall f, fcb, yes),
    (dirMatches) ->
      cb null,
        files: (lo.without nextFiles, dirMatches...)
        dirs: dirMatches
        patterns: patterns

mapToProperty = (prop, l) -> l.map (it) -> it[prop]

recurseIgnore = ({invert, ignoreFileObjs}, dir, cb) ->
  (err, opts) ->
    {
      files: matchFiles
      dirs: matchDirs
      patterns
    } = opts
    if err then cb err
    else switch matchDirs.length
      when 0 then cb null, {files: matchFiles, dirs: []}
      else async.map matchDirs,
        ((matchedDir, mcb) ->
          getTracked matchedDir, {invert, ignoreFileObjs, patterns},
            (err, res) -> if err then mcb err else mcb null, {matchedDir, res}),
        (err, results) ->
          if err then cb err
          else
            cleanedDirs = mapToProperty 'matchedDir', results
            flattened = mapToProperty 'res', results
            cleanedDirs = cleanedDirs.concat mapToProperty 'dirs', flattened
            cleanedFiles = mapToProperty 'files', flattened
            cb null,
              files: lo.uniq lo.flatten matchFiles.concat cleanedFiles
              dirs: lo.uniq lo.flatten cleanedDirs

optionalOpts = (fun) -> (arg, opts, cb) ->
  if typeof opts is 'function' then fun arg, null, opts else fun arg, opts, cb

getTracked = optionalOpts (dir, opts = {}, cb) ->
  {
    invert = no                         # immutable
    ignoreFileObjs = defaultIgnoreFiles # immutable
    patterns = defaultPatterns dir      # added to on each recursion
  } = opts
  async.waterfall [
    ((wcb) -> fs.readdir dir, wcb)
    getNewIgnoreFiles dir, ignoreFileObjs
    getNewPatterns dir
    # append to old patterns
    (files, ignorePatternsFromDir, wcb) ->
      patterns = patterns.concat ignorePatternsFromDir
      wcb null, files, patterns
    applyPatterns invert
    splitFilesDirectories],
    recurseIgnore {invert, ignoreFileObjs}, dir, cb

module.exports = {
  getTracked
  IgnoreFile
  IgnorePattern
  regexFromIgnore
  defaultIgnoreFiles
  defaultPatterns
}
