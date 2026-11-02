import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('problems mirror saveAgent; the callable input has E.164 phones and no rating or photo', () {
    expect(const AgentProfile().problems().keys, ['name', 'earbNo', 'phone', 'whatsapp']);
    const p = AgentProfile(name: ' Mercy ', earbNo: 'EARB/1', phone: '0711 000 111', whatsapp: '0711000111', rating: 4.5, photo: 'x');
    expect(p.problems(), isEmpty);
    expect(p.toCallable(), {
      'name': 'Mercy',
      'earbNo': 'EARB/1',
      'phone': '+254711000111',
      'whatsapp': '+254711000111',
      'languages': ['en'],
      'active': true,
    });
    expect(const AgentProfile(name: 'Mercy', earbNo: 'E', phone: '0711000111', whatsapp: '0711000111', languages: []).problems().keys, ['languages']);
  });

  test('reads an agents document', () {
    final a = AgentProfile.fromDoc('agent-1', {'name': 'Brian', 'earbNo': 'E2', 'languages': ['sw'], 'active': true, 'rating': 4, 'responseMins': 25});
    expect((a.id, a.languages.single, a.rating, a.responseMins, a.photo), ('agent-1', 'sw', 4.0, 25, null));
  });
}
