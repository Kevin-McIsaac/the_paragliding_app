/// Whether a remote file has changed since the copy on disk was taken.
///
/// Shared by every bulk download the app keeps locally - the airspace country
/// exports and the site catalogue - because the answer is the same question in
/// both cases, and getting it wrong is expensive in both directions: too eager
/// re-downloads megabytes for nothing, too lax leaves stale data in place.
///
/// Pure, so the branches are tested without a network. Kept out of either
/// service so a fix to the freshness rule cannot be applied to one and missed in
/// the other, which is what happened when the second copy was pasted from the
/// first.
///
/// Prefers ETag, falls back to Last-Modified, and only falls back to age when
/// neither side offers something comparable. A server that sends no validators
/// leaves nothing to compare, so age is the last resort rather than the rule.
bool isRemoteNewer({
  required String? storedEtag,
  required String? storedLastModified,
  required String? remoteEtag,
  required String? remoteLastModified,
  required int ageInDays,
  int maxAgeInDays = 30,
}) {
  if (remoteEtag != null && storedEtag != null) {
    return remoteEtag != storedEtag;
  }
  if (remoteLastModified != null && storedLastModified != null) {
    return remoteLastModified != storedLastModified;
  }
  return ageInDays > maxAgeInDays;
}
