enum FeatureAccessDecision {
  allowed,
  requiresPro,
  checking,

  /// Reserved for the later verified-cache/network policy, not emitted in N1.
  requiresConnection,
  featureUnavailable,
}
