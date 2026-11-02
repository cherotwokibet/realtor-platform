import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseCsv', () {
    test('quotes, escaped quotes, commas and line breaks inside a field, CRLF, BOM', () {
      final t = parseCsv('﻿a,b,c\r\n"x, y","say ""hi""","two\nlines"\r\n1,,3');
      expect(t, [
        ['a', 'b', 'c'],
        ['x, y', 'say "hi"', 'two\nlines'],
        ['1', '', '3'],
      ]);
    });
  });

  group('ListingCsv', () {
    const header = 'Title,Purpose,Type,Beds,Baths,Price KES,Deposit Months,Lat,Lng,Area,Amenities,Agent Id,Notes';

    test('a good sheet becomes typed rows; prices read as people write them; unknown columns are ignored', () {
      final r = ListingCsv.parse('$header\n'
          '"2 bedroom apartment, Kilimani",Rent,Apartment,2,2,"KES 65,000",2,-1.29,36.78,kilimani,parking; borehole ,agent-wanjiku,call first\n'
          '\n'
          'Plot in Ruaka,sale,land,0,0,4 500 000,,-1.2,36.77,ruaka,,agent-otieno,\n');
      expect(r.ok, isTrue, reason: '${r.problems}');
      expect(r.rows.map((x) => x.line), [2, 4]);
      expect(r.rows.first.row, {
        'title': '2 bedroom apartment, Kilimani',
        'purpose': 'rent',
        'type': 'apartment',
        'beds': 2,
        'baths': 2,
        'priceKES': 65000,
        'depositMonths': 2,
        'lat': -1.29,
        'lng': 36.78,
        'area': 'kilimani',
        'amenities': ['parking', 'borehole'],
        'agentId': 'agent-wanjiku',
      });
      expect(r.rows.last.row['priceKES'], 4500000);
      expect(r.rows.last.row.containsKey('depositMonths'), isFalse, reason: 'empty optional cells are left out');
    });

    test('a description column comes through as text, commas and all (P7-s02)', () {
      final csv = ListingCsv.parse('title,purpose,type,beds,baths,priceKES,lat,lng,area,agentId,Description\n'
          'Flat in Ruaka,rent,apartment,1,1,25000,-1.2,36.7,ruaka,agent-1,"Quiet, near the market."\n');
      expect(csv.ok, isTrue);
      expect(csv.rows.single.row['description'], 'Quiet, near the market.');
    });

    test('bad rows are reported by line; good rows still come through', () {
      final r = ListingCsv.parse('$header\n'
          'Ok,rent,studio,0,1,20000,1,-1.3,36.8,kilimani,,agent-a,\n'
          'Bad,lease,castle,two,1,20000.50,1,-1.3,36.8,kilimani,,,\n');
      expect(r.rows.map((x) => x.line), [2]);
      expect(r.problems.single.line, 3);
      expect(r.problems.single.problem, allOf(contains('purpose "lease"'), contains('type "castle"'), contains('beds "two"'),
          contains('priceKES "20000.50"'), contains('agentId is empty')));
    });

    test('missing columns or an empty file stop at the header', () {
      expect(ListingCsv.parse('title,purpose\nx,rent').problems.single.problem, startsWith('missing columns: type, beds'));
      expect(ListingCsv.parse('').problems.single.problem, 'the file is empty');
      expect(ListingCsv.parse(header).problems.single.problem, 'no listings under the header');
    });
  });
}
