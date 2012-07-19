// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('source');

#import('io.dart');
#import('package.dart');
#import('pubspec.dart');
#import('system_cache.dart');
#import('version.dart');

/**
 * A source from which to install packages.
 *
 * Each source has many packages that it looks up using [PackageId]s. The source
 * is responsible for installing these packages to the package cache.
 */
class Source {
  /**
   * The name of the source. Should be lower-case, suitable for use in a
   * filename, and unique accross all sources.
   */
  abstract String get name();

  /**
   * Whether this source's packages should be cached in Pub's global cache
   * directory.
   *
   * A source should be cached if it requires network access to retrieve
   * packages. It doesn't need to be cached if all packages are available
   * locally.
   */
  abstract bool get shouldCache();

  /**
   * The system cache with which this source is registered.
   */
  SystemCache get systemCache() {
    assert(_systemCache != null);
    return _systemCache;
  }

  /**
   * The system cache variable. Set by [_bind].
   */
  SystemCache _systemCache;

  /**
   * The root directory of this source's cache within the system cache.
   *
   * This shouldn't be overridden by subclasses.
   */
  String get systemCacheRoot() => join(systemCache.rootDir, name);

  /**
   * Records the system cache to which this source belongs.
   *
   * This should only be called once for each source, by [SystemCache.register].
   * It should not be overridden by base classes.
   */
  void bind(SystemCache systemCache) {
    assert(_systemCache == null);
    this._systemCache = systemCache;
  }

  /**
   * Get the list of all versions that exist for the package described by
   * [description].
   *
   * Note that this does *not* require the packages to be installed, which is
   * the point. This is used during version resolution to determine which
   * package versions are available to be installed (or already installed).
   *
   * By default, this assumes that each description has a single version and
   * uses [describe] to get that version.
   */
  Future<List<Version>> getVersions(description) {
    return describe(new PackageId(this, Version.none, description))
      .transform((pubspec) => [pubspec.version]);
  }

  /**
   * Loads the (possibly remote) pubspec for the package version identified by
   * [id]. This may be called for packages that have not yet been installed
   * during the version resolution process.
   *
   * For cached sources, by default this uses [installToSystemCache] to get the
   * pubspec. There is no default implementation for non-cached sources; they
   * must implement it manually.
   */
  Future<Pubspec> describe(PackageId id) {
    if (!shouldCache) throw "Source $name must implement describe(id).";
    return installToSystemCache(id).transform((package) => package.pubspec);
  }

  /**
   * Installs the package identified by [id] to [path]. Returns a [Future] that
   * completes when the installation was finished. The [Future] should resolve
   * to true if the package was found in the source and false if it wasn't. For
   * all other error conditions, it should complete with an exception.
   *
   * [path] is guaranteed not to exist, and its parent directory is guaranteed
   * to exist.
   *
   * This doesn't need to be implemented if [installToSystemCache] is
   * implemented.
   */
  Future<bool> install(PackageId id, String path) {
    throw "Either install or installToSystemCache must be implemented for "
      "source $name."
  }

  /**
   * Installs the package identified by [id] to the system cache. This is only
   * called for sources with [shouldCache] set to true.
   *
   * By default, this uses [systemCacheDirectory] and [install].
   */
  Future<Package> installToSystemCache(PackageId id) {
    var path = systemCacheDirectory(id);
    return exists(path).chain((exists) {
      // TODO(nweiz): better error handling
      if (exists) throw 'Package $id is already installed.';
      return ensureDir(dirname(path));
    }).chain((_) {
      return install(id, path);
    }).chain((found) {
      if (!found) throw 'Package $id not found.';
      return Package.load(path, systemCache.sources);
    });
  }

  /**
   * Returns the directory in the system cache that the package identified by
   * [id] should be installed to. This should return a path to a subdirectory of
   * [systemCacheRoot].
   *
   * This doesn't need to be implemented if [shouldCache] is false, or if
   * [installToSystemCache] is implemented.
   */
  String systemCacheDirectory(PackageId id) =>
    join(systemCacheRoot, packageName(id.description));

  /**
   * When a [Pubspec] is parsed, it reads in the description for each
   * dependency. It is up to the dependency's [Source] to determine how that
   * should be interpreted. This will be called during parsing to validate that
   * the given [description] is well-formed according to this source. It should
   * return if the description is valid, or throw a [FormatException] if not.
   */
  void validateDescription(description) {}

  /**
   * Returns a human-friendly name for the package described by [description].
   * This method should be light-weight. It doesn't need to validate that the
   * given package exists.
   *
   * The package name should be lower-case and suitable for use in a filename.
   * It may contain forward slashes.
   */
  String packageName(description) => description;

  /**
   * Returns whether or not [description1] describes the same package as
   * [description2] for this source. This method should be light-weight. It
   * doesn't need to validate that either package exists.
   *
   * By default, this assumes both descriptions are strings and compares them
   * for equality.
   */
  bool descriptionsEqual(description1, description2) =>
    description1 == description2;
}
