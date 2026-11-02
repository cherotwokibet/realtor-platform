import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  const ok = OffPlanProject(
    name: 'Sample Heights',
    developer: 'Sample Developers Ltd',
    area: 'kilimani',
    completion: '2028-06',
    units: [OffPlanUnit(type: 'apartment', beds: 2, sizeSqm: 84, fromKES: 7200000, available: 40)],
    paymentPlan: [(stage: 'Deposit', percent: 10), (stage: 'On handover', percent: 90)],
  );

  test('a complete project has no problems and goes to saveProject as its input', () {
    expect(ok.problems(), isEmpty);
    final c = ok.toCallable();
    expect(c.containsKey('slug'), isFalse);
    expect(c['units'], [{'type': 'apartment', 'beds': 2, 'sizeSqm': 84, 'fromKES': 7200000, 'available': 40}]);
    expect(c['paymentPlan'], [{'stage': 'Deposit', 'percent': 10}, {'stage': 'On handover', 'percent': 90}]);
  });

  test('the payment plan must make 100%, the month is YYYY-MM, units are checked', () {
    final bad = OffPlanProject(
      name: 'Sa',
      developer: ok.developer,
      area: '',
      completion: '2028-13',
      units: const [OffPlanUnit(fromKES: 5000)],
      paymentPlan: const [(stage: 'Deposit', percent: 10)],
    ).problems();
    expect(bad.keys, containsAll(['name', 'area', 'completion', 'units', 'paymentPlan']));
    expect(bad['paymentPlan'], 'The stages add up to 10%; they must make 100%.');
    expect(bad['units'], 'From price: KES 100,000 or more.');
  });

  test('fromDoc reads what saveProject stored', () {
    final p = OffPlanProject.fromDoc('sample-heights', {...ok.toCallable(), 'fromKES': 7200000, 'published': true});
    expect(p.slug, 'sample-heights');
    expect(p.units.single.sizeSqm, 84);
    expect(p.planTotal, 100);
    expect(p.fromKES, 7200000);
    expect(p.published, isTrue);
  });
}
