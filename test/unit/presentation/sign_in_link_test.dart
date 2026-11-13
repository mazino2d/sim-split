import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';

void main() {
  test('the link to copy on the gate is the kept invite link (#109)', () {
    expect(
      signInLinkFor(
          Uri.parse('https://simsplit.web.app/sign-in?from=%2Fjoin%2FaB3dE5')),
      Uri.parse('https://simsplit.web.app/join/aB3dE5'),
    );
  });

  test('without an invite, the link is the app itself', () {
    expect(signInLinkFor(Uri.parse('https://simsplit.web.app/sign-in')),
        Uri.parse('https://simsplit.web.app/'));
    // Only a path on this site, never another site.
    expect(
        signInLinkFor(Uri.parse(
            'https://simsplit.web.app/sign-in?from=https://evil.example')),
        Uri.parse('https://simsplit.web.app/'));
    expect(
        signInLinkFor(Uri.parse(
            'https://simsplit.web.app/sign-in?from=%2F%2Fevil.example')),
        Uri.parse('https://simsplit.web.app/'));
  });
}
