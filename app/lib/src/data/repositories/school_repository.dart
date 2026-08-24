import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../entities.dart';

/// School registration (via the `create_school` RPC), memberships and
/// lookups. Governing RLS: members see their own schools; the founder becomes
/// SUPER_ADMIN automatically.
class SchoolRepository {
  final SupabaseClient _client;

  SchoolRepository(this._client);

  Future<School> createSchool({
    required String name,
    required String schoolType,
    required String subsystem,
    String? code,
    String? address,
    String? phone,
    String? email,
    String? region,
    String? division,
    String? subDivision,
    String? logoUrl,
    File? logoFile,
  }) async {
    // Sanitize logoUrl: never store a local file path like "/Users/..." or "file://"
    // Only http(s) URLs are valid for direct storage; file uploads are handled via storage bucket
    String? sanitizedLogoUrl;
    if (logoUrl != null) {
      final t = logoUrl.trim();
      if (t.isNotEmpty && (t.startsWith('http://') || t.startsWith('https://'))) {
        sanitizedLogoUrl = t;
      } else if (t.isNotEmpty) {
        debugPrint('SchoolRepository: ignoring non-http logoUrl (likely local path): $t');
        sanitizedLogoUrl = null;
      }
    }

    // First create the school to get its ID
    final id = await _client.rpc('create_school', params: {
      'p_name': name.trim(),
      'p_school_type': schoolType,
      'p_subsystem': subsystem,
      'p_code': code?.trim().isEmpty ?? true ? null : code!.trim(),
      'p_address': address,
      'p_phone': phone,
      'p_email': email,
      'p_region': region,
      'p_division': division,
      'p_sub_division': subDivision,
      'p_logo_url': sanitizedLogoUrl,
    });

    String? finalLogoUrl = sanitizedLogoUrl;

    // If logo file provided, upload directly to the school's folder
    // Non-blocking: logo failures should NOT fail the whole school creation
    if (logoFile != null) {
      try {
        final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final path = '$id/$fileName';
        await _client.storage.from('school-logos').upload(path, logoFile);
        finalLogoUrl = _client.storage.from('school-logos').getPublicUrl(path);
        debugPrint('SchoolRepository: uploaded to $path -> $finalLogoUrl');
        // Update the school record with the logo URL — try direct, fallback to RPC
        bool updated = false;
        try {
          await _client.from('schools').update({'logo_url': finalLogoUrl}).eq('id', id);
          // Verify
          final check = await _client.from('schools').select('logo_url').eq('id', id).maybeSingle();
          if (check != null && (check['logo_url'] as String?) == finalLogoUrl) {
            updated = true;
            debugPrint('SchoolRepository: logo_url direct update verified');
          } else {
            debugPrint('SchoolRepository: direct update appeared to succeed but verify failed: $check');
          }
        } catch (e) {
          debugPrint('SchoolRepository: logo_url direct update failed (will try RPC): $e');
        }
        if (!updated) {
          try {
            await _client.rpc('update_school_logo', params: {'p_school': id, 'p_logo_url': finalLogoUrl});
            debugPrint('SchoolRepository: logo_url RPC update succeeded');
          } catch (e) {
            debugPrint('SchoolRepository: logo_url RPC update also failed: $e');
          }
        }
      } catch (e) {
        // Bucket missing, RLS, network — log and continue without logo
        debugPrint('SchoolRepository: logo upload failed (non-fatal), continuing without logo: $e');
        // Do not rethrow — school was created successfully
      }
    }

    // Fetch the freshly created school. RLS may briefly lag after RPC,
    // so handle null gracefully by constructing locally.
    try {
      final rows = await _client.from('schools').select().eq('id', id).maybeSingle();
      if (rows != null) return School.fromMap(rows as Map<String, dynamic>);
      debugPrint('SchoolRepository: schools select returned null for $id, constructing locally');
    } catch (e) {
      debugPrint('SchoolRepository: schools select failed: $e — constructing locally');
    }
    // Fallback: construct School from known inputs so onboarding can continue
    return School(
      id: id.toString(),
      name: name.trim(),
      code: code?.trim().isEmpty ?? true ? null : code!.trim(),
      schoolType: schoolType,
      subsystem: subsystem,
      logoUrl: finalLogoUrl,
      address: address,
      phone: phone,
      email: email,
      region: region,
    );
  }

  /// The current user's memberships including the joined school object.
  Future<List<SchoolMembership>> myMemberships() async {
    final rows = await _client
        .from('school_memberships')
        .select('*, school:schools(*)');
    final list = rows as List<dynamic>;
    return list
        .map((r) {
          final m = r as Map<String, dynamic>;
          return SchoolMembership.fromMap(
            m,
            joinedSchool: m['school'] as Map<String, dynamic>?,
          );
        })
        .toList();
  }
}