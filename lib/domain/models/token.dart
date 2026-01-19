class TokenModel {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final int refreshExpiresIn;
  final String tokenType;
  final String scope;
  final String sessionState;
  final int notBeforePolicy;

  TokenModel(
      {required this.accessToken,
      required this.refreshToken,
      required this.expiresIn,
      required this.refreshExpiresIn,
      required this.tokenType,
      required this.scope,
      required this.sessionState,
      required this.notBeforePolicy});

  factory TokenModel.fromJson(Map<String, dynamic> json) {
    return TokenModel(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresIn: json['expires_in'],
      refreshExpiresIn: json['refresh_expires_in'],
      tokenType: json['token_type'],
      scope: json['scope'],
      sessionState: json['session_state'],
      notBeforePolicy: json['not-before-policy'],
    );
  }
}