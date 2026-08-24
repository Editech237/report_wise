import 'dart:async';

/// Simple in-memory cache for static academic lookups that rarely change
/// (education_types, cycles, levels, series, specialties, subjects).
/// Avoids refetching the same national defaults on every screen.
class AcademicCache {
  static final AcademicCache _instance = AcademicCache._internal();
  factory AcademicCache() => _instance;
  AcademicCache._internal();

  final Map<String, _CacheEntry> _cache = {};

  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  void set<T>(String key, T value, {Duration ttl = const Duration(minutes: 10)}) {
    _cache[key] = _CacheEntry(value as Object, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _cache.remove(key);
  void clear() => _cache.clear();

  Future<T> getOrFetch<T>(String key, Future<T> Function() fetcher, {Duration ttl = const Duration(minutes: 10)}) async {
    final cached = get<T>(key);
    if (cached != null) return cached;
    final fresh = await fetcher();
    set(key, fresh, ttl: ttl);
    return fresh;
  }
}

class _CacheEntry {
  final Object value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
}
