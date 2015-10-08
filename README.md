.*ignore
=======

A module to traverse directories of git repositories according to `.gitignore` (and other specified files). Written because I couldn't figure out how to use any of the other options. Made for use in [cpm](https://github.com/cosmicexplorer/cpm).

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
    - defaults to `[new IgnorePattern('.git', 0, true)]`.
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

This class represents a pattern drawn from a `.gitignore`-like file. It creates a regular expression and matches it against files encountered in the file system during the operation of `getTracked`.

```javascript
new IgnorePattern(
  pattern, // string
  precedence, // integer
  negated, // boolean
  directory // string
)
```

- `pattern`: wildcard pattern, taken relative to the directory of the file the pattern was found in
- `precedence`: as in `IgnoreFile`
- `negated`: whether the pattern had a `!` at front in the ignore file
- `directory`: base directory where pattern takes effect

### Git Default

The default option for this is contained in `require('dot-star-ignore').defaultPatterns`, which is equivalent to `[new IgnorePattern('.git', 0, true)]`.

### Usage Notes

Wildcards apply to all lower directories, just like the real git client! For non-recursive wildcarding, use `/<pattern>`. For example, to ignore `.js` files, but only in the folder containing a `.gitignore` file, use `/*.js` as the ignore pattern.

# Auxiliary Functions

```javascript
function regexFromIgnore(pattern, flags) {
```

- `pattern`: wildcard pattern to create a regular expression from.
- `flags`: flags used in `RegExp` constructor.

Auxiliary function used internally to convert a wildcard pattern into a regex for the same pattern.

# License

[GPLv3 or any later version](GPL.md)
