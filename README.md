.*ignore
========

A module to get tracked files in git repositories (according to `.gitignore`), or other specified ignore files (`.npmignore`, etc). Written because I couldn't figure out how to use any of the other options. Made for use in [cpm](https://github.com/cosmicexplorer/cpm). A git repository is not required to use this module.

# Usage
```javascript
require('dot-star-ignore').getTracked('.', function (err, result) {
  if (err) { console.error(err); }
  else {
    console.log("files tracked by git in folder '.': ");
    console.log(result.files.join('\n'));
  }
});
```

# API
```javascript
function getTracked(dir, [options,] callback) {
```

- `dir`: root directory to perform traversal on. `ignore` follows symlinks, so ensure your directory tree is not cyclical. If `dir` is a relative path, it is assumed to be relative to `process.cwd()`.
- `options` is an object with parameters:
  - `invert`: if truthy, returns files (or function, if `filter` is on) *matching* the ignored patterns, instead of files ignored by the patterns.
  - `ignoreFiles`: array of `IgnoreFile` objects, which are specified [below](#ignorefile).
    - defaults to `[new IgnoreFile('.gitignore', 0)]`.
  - `patterns`: array of `IgnorePattern` objects, which are specified [below](#ignorepattern).
    - defaults to `[new IgnorePattern('.git', 0, '.')]`.
- `callback(err, results)`: bubbles up all `fs` errors, returns matched files and directories.

Returns object with keys `files` and `dirs`, containing the files and directories tracked (or not, if you use `invert`) by git (or whatever `ignoreFiles` you specify).

# Objects

## IgnoreFile

This class represents a file which provides `.gitignore`-like wildcard patterns to ignore from the current directory, and directories below it.

```javascript
new IgnoreFile(
  name, // string
  precedence // integer
)
```

- `name`: exact text matching ignore file; `.gitignore`, `.npmignore`, etc. Matches filenames, not their paths (so `../.gitignore` isn't allowed).
- `precedence`: positive integer specifying which files take precedence over others. If two `IgnoreFile` objects have the same precedence and contain similar patterns, the resulting behavior is undefined.

### Git Default

The default option for this is contained in `require('dot-star-ignore').defaultIgnoreFiles`, which is equivalent to `[new IgnoreFile('.gitignore', 0)]`.

### Usage Notes

Precedence starts from `0` and goes to `Infinity`. To implement something like npm's ignore patterns for publishing, you can call:

```javascript
var ignore = require('dot-star-ignore');
var newIgnoreFile = new ignore.IgnoreFile('.npmignore', 1);
var ignoreFiles = ignore.defaultIgnoreFiles.concat(newIgnoreFile);
ignore.getTracked(<dir>, {ignoreFiles: ignoreFiles}, <callback>);
```

Then, patterns in `.npmignore` files will take precedence over `.gitignore` patterns in the same directory.

## IgnorePattern

This class represents a pattern drawn from a `.gitignore`-like file. It creates a regular expression and matches it against files encountered in the file system during the operation of `getTracked`. Note that **all** of the below options should be given for the `IgnorePattern` constructor.

```javascript
new IgnorePattern({
  pattern: // string
  precedence: // integer
  dir: // string
})
```

- `pattern`: wildcard pattern, taken relative to the directory of the file the pattern was found in.
- `precedence`: as in `IgnoreFile`.
- `dir`: base directory where pattern takes effect.

### Git Default

The default option for this is contained in `require('dot-star-ignore').defaultPatterns`, which is equivalent to `[new IgnorePattern('.git', 0, '.')]`.

### Usage Notes

Wildcards apply to all lower directories, just like the real git client! For non-recursive wildcarding, use `/<pattern>`. For example, to ignore `.js` files, but only in the folder containing a `.gitignore` file, use `/*.js` as the ignore pattern.

To ignore a file named `ignore_me` (in addition to any patterns given in `.gitignore` or other files) in the current directory and lower by giving a pattern to `getTracked` (with precedence 0), do the following:

```javascript
var ignore = require('dot-star-ignore');
var newIgnorePattern = new ignore.IgnorePattern({
  pattern: '/ignore_me',
  precedence: 0,
  dir: '.'
});
var ignorePatterns = ignore.defaultPatterns.concat(newIgnorePattern);
ignore.getTracked(<dir>, {patterns: ignorePatterns}, <callback>);
```

# Auxiliary Functions

## getRelativePathSequence

```javascript
function getRelativePathSequence(dir, file) {
```

- `dir`: directory to take relative path from.
- `file`: file to take relative path to.

Return an array of paths concatenating sections of the path, from the end, in no particular order. For example:

```javascript
getRelativePathSequence('.', 'foo/bar/baz');
// => [ 'foo/bar/baz', 'baz', 'bar/baz' ]
```

## regexFromWildcard

```javascript
function regexFromWildcard(pattern) {
```

- `pattern`: wildcard pattern to create a regular expression from.

Convert a wildcard pattern into a regex for files matching the given wildcard pattern. Returns a string suitable for conversion into a `RegExp` object. Supports everything `bash` does.

# License

[GPLv3 or any later version](GPL.md)
