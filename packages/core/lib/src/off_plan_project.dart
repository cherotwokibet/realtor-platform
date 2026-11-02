// Off-plan projects (P5-s06): a development sold before it is finished.
// The admin edits them; `saveProject` in Functions checks the same rules
// as OffPlanProject.problems and works out the "from" price.

/// Unit types, as functions/src/model/schema.ts UNIT_TYPES.
const offPlanUnitTypes = ['studio', 'apartment', 'maisonette', 'townhouse', 'villa', 'plot', 'commercial'];

class OffPlanUnit {
  const OffPlanUnit({this.type = 'apartment', this.beds = 1, this.sizeSqm, this.fromKES = 0, this.available = 0});
  final String type;
  final int beds;
  final int? sizeSqm;
  final int fromKES, available;

  factory OffPlanUnit.fromDoc(Map<Object?, Object?> d) => OffPlanUnit(
        type: d['type'] as String? ?? 'apartment',
        beds: (d['beds'] as num?)?.toInt() ?? 0,
        sizeSqm: (d['sizeSqm'] as num?)?.toInt(),
        fromKES: (d['fromKES'] as num?)?.toInt() ?? 0,
        available: (d['available'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toCallable() =>
      {'type': type, 'beds': beds, if (sizeSqm != null) 'sizeSqm': sizeSqm, 'fromKES': fromKES, 'available': available};

  String? problem() {
    if (!offPlanUnitTypes.contains(type)) return 'Pick a unit type.';
    if (beds < 0 || beds > 10) return 'Bedrooms: 0 to 10.';
    if (sizeSqm != null && (sizeSqm! < 10 || sizeSqm! > 5000)) return 'Size: 10 to 5,000 m².';
    if (fromKES < 100000 || fromKES > 2000000000) return 'From price: KES 100,000 or more.';
    if (available < 0 || available > 5000) return 'Available: 0 to 5,000.';
    return null;
  }
}

typedef OffPlanStage = ({String stage, int percent});

class OffPlanProject {
  const OffPlanProject({
    this.slug,
    this.name = '',
    this.developer = '',
    this.area = '',
    this.summary = '',
    this.completion = '',
    this.units = const [OffPlanUnit()],
    this.paymentPlan = const [],
    this.published = false,
    this.fromKES = 0,
    this.updatedAt,
  });

  /// Null for a new project; the Function makes it from the name.
  final String? slug;
  final String name, developer, area, summary;

  /// Expected handover, `YYYY-MM`.
  final String completion;
  final List<OffPlanUnit> units;
  final List<OffPlanStage> paymentPlan;
  final bool published;

  /// The cheapest unit, as the Function last saved it.
  final int fromKES;
  final DateTime? updatedAt;

  int get planTotal => paymentPlan.fold(0, (sum, s) => sum + s.percent);

  factory OffPlanProject.fromDoc(String slug, Map<String, Object?> d, {DateTime? updatedAt}) => OffPlanProject(
        slug: slug,
        name: d['name'] as String? ?? slug,
        developer: d['developer'] as String? ?? '',
        area: d['area'] as String? ?? '',
        summary: d['summary'] as String? ?? '',
        completion: d['completion'] as String? ?? '',
        units: [for (final u in (d['units'] as List<Object?>?) ?? const []) OffPlanUnit.fromDoc(u! as Map<Object?, Object?>)],
        paymentPlan: [
          for (final s in (d['paymentPlan'] as List<Object?>?) ?? const [])
            (stage: (s! as Map)['stage'] as String? ?? '', percent: ((s as Map)['percent'] as num?)?.toInt() ?? 0),
        ],
        published: d['published'] == true,
        fromKES: (d['fromKES'] as num?)?.toInt() ?? 0,
        updatedAt: updatedAt,
      );

  /// What is wrong, by field, as `saveProject` would refuse it.
  Map<String, String> problems() {
    final unit = units.map((u) => u.problem()).whereType<String>().firstOrNull;
    return {
      if (name.trim().length < 3 || name.trim().length > 80) 'name': 'Use 3 to 80 characters.',
      if (developer.trim().length < 2 || developer.trim().length > 80) 'developer': 'Who is building it?',
      if (area.isEmpty) 'area': 'Pick the area.',
      if (summary.length > 5000) 'summary': 'Under 5,000 characters.',
      if (!_month.hasMatch(completion.trim())) 'completion': 'Handover month as YYYY-MM, e.g. 2028-06.',
      if (units.isEmpty || units.length > 20) 'units': 'Between 1 and 20 unit types.',
      if (unit != null) 'units': unit,
      if (paymentPlan.isEmpty || paymentPlan.length > 12) 'paymentPlan': 'Between 1 and 12 stages.',
      if (paymentPlan.any((s) => s.stage.trim().length < 2 || s.stage.trim().length > 60 || s.percent < 1 || s.percent > 100))
        'paymentPlan': 'Each stage needs a name and 1 to 100%.',
      if (paymentPlan.isNotEmpty && planTotal != 100) 'paymentPlan': 'The stages add up to $planTotal%; they must make 100%.',
    };
  }

  Map<String, Object?> toCallable() => {
        if (slug != null) 'slug': slug,
        'name': name.trim(),
        'developer': developer.trim(),
        'area': area,
        'summary': summary.trim(),
        'completion': completion.trim(),
        'units': [for (final u in units) u.toCallable()],
        'paymentPlan': [for (final s in paymentPlan) {'stage': s.stage.trim(), 'percent': s.percent}],
        'published': published,
      };
}

final _month = RegExp(r'^20\d\d-(0[1-9]|1[0-2])$');
