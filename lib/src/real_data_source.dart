class RealDataSource {
  const RealDataSource({
    required this.datasource,
    required this.originalDatasource,
    required this.isCacheAvailable,
  });

  final String datasource;
  final String originalDatasource;
  final bool isCacheAvailable;
}
