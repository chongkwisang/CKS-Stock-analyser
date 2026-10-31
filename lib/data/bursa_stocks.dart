/// Built-in list of well-known Bursa Malaysia counters (Yahoo symbols use the
/// 4-digit stock code + ".KL"). Used for offline search and the market movers
/// board. Any other counter can still be found through online search.
class BursaStock {
  final String code;
  final String name;
  final String sector;
  const BursaStock(this.code, this.name, this.sector);
  String get symbol => '$code.KL';
}

const String klciSymbol = '^KLSE';

const List<BursaStock> klciStocks = [
  BursaStock('1155', 'MAYBANK', 'Financial Services'),
  BursaStock('1295', 'PBBANK', 'Financial Services'),
  BursaStock('1023', 'CIMB', 'Financial Services'),
  BursaStock('5347', 'TENAGA', 'Utilities'),
  BursaStock('5225', 'IHH', 'Health Care'),
  BursaStock('5819', 'HLBANK', 'Financial Services'),
  BursaStock('1066', 'RHBBANK', 'Financial Services'),
  BursaStock('1015', 'AMBANK', 'Financial Services'),
  BursaStock('1082', 'HLFG', 'Financial Services'),
  BursaStock('6947', 'CDB', 'Telecommunications'),
  BursaStock('6012', 'MAXIS', 'Telecommunications'),
  BursaStock('4863', 'TM', 'Telecommunications'),
  BursaStock('5183', 'PCHEM', 'Industrial Products'),
  BursaStock('6033', 'PETGAS', 'Utilities'),
  BursaStock('5681', 'PETDAG', 'Consumer Products'),
  BursaStock('3816', 'MISC', 'Transportation'),
  BursaStock('8869', 'PMETAL', 'Industrial Products'),
  BursaStock('1961', 'IOICORP', 'Plantation'),
  BursaStock('2445', 'KLK', 'Plantation'),
  BursaStock('5285', 'SDG', 'Plantation'),
  BursaStock('4197', 'SIME', 'Consumer Products'),
  BursaStock('4707', 'NESTLE', 'Consumer Products'),
  BursaStock('7084', 'QL', 'Consumer Products'),
  BursaStock('4065', 'PPB', 'Consumer Products'),
  BursaStock('5296', 'MRDIY', 'Consumer Products'),
  BursaStock('3182', 'GENTING', 'Consumer Products'),
  BursaStock('4715', 'GENM', 'Consumer Products'),
  BursaStock('5398', 'GAMUDA', 'Construction'),
  BursaStock('6742', 'YTLPOWR', 'Utilities'),
  BursaStock('4677', 'YTL', 'Utilities'),
  BursaStock('5211', 'SUNWAY', 'Industrial Products'),
];

const List<BursaStock> otherPopularStocks = [
  BursaStock('7277', 'DIALOG', 'Energy'),
  BursaStock('7113', 'TOPGLOV', 'Health Care'),
  BursaStock('7106', 'SUPERMX', 'Health Care'),
  BursaStock('5168', 'HARTA', 'Health Care'),
  BursaStock('0166', 'INARI', 'Technology'),
  BursaStock('0097', 'VITROX', 'Technology'),
  BursaStock('3867', 'MPI', 'Technology'),
  BursaStock('5292', 'UWC', 'Technology'),
  BursaStock('0128', 'FRONTKN', 'Technology'),
  BursaStock('5005', 'UNISEM', 'Technology'),
  BursaStock('0138', 'MYEG', 'Technology'),
  BursaStock('5249', 'IOIPG', 'Property'),
  BursaStock('8664', 'SPSETIA', 'Property'),
  BursaStock('5148', 'UEMS', 'Property'),
  BursaStock('1171', 'MBSB', 'Financial Services'),
  BursaStock('1818', 'BURSA', 'Financial Services'),
  BursaStock('5139', 'AEONCR', 'Financial Services'),
  BursaStock('5210', 'BUMI', 'Energy'),
  BursaStock('7293', 'YINSON', 'Energy'),
  BursaStock('5199', 'HIBISCS', 'Energy'),
  BursaStock('5246', 'WPRTS', 'Transportation'),
  BursaStock('5099', 'CAPITALA', 'Transportation'),
  BursaStock('4588', 'UMW', 'Consumer Products'),
  BursaStock('5326', '99SMART', 'Consumer Products'),
  BursaStock('6599', 'AEON', 'Consumer Products'),
  BursaStock('3689', 'F&N', 'Consumer Products'),
  BursaStock('2836', 'CARLSBG', 'Consumer Products'),
  BursaStock('3255', 'HEIM', 'Consumer Products'),
  BursaStock('5263', 'SUNCON', 'Construction'),
  BursaStock('3336', 'IJM', 'Construction'),
  BursaStock('5032', 'BIPORT', 'Transportation'),
  BursaStock('7204', 'D&O', 'Technology'),
  BursaStock('5222', 'FGV', 'Plantation'),
  BursaStock('2291', 'GENP', 'Plantation'),
  BursaStock('6888', 'AXIATA', 'Telecommunications'),
  BursaStock('5031', 'TIMECOM', 'Telecommunications'),
];

List<BursaStock> get allKnownStocks => [...klciStocks, ...otherPopularStocks];

BursaStock? findKnown(String symbol) {
  for (final s in allKnownStocks) {
    if (s.symbol == symbol) return s;
  }
  return null;
}
