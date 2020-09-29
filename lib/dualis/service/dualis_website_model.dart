import 'package:dhbwstudentapp/dualis/model/exam.dart';

class DualisUrls {
  String courseResultUrl;
  String studentResultsUrl;
  String logoutUrl;
  String mainPageUrl;
  String monthlyScheduleUrl;

  Map<String, String> semesterCourseResultUrls = {};
}

class DualisSemester {
  final String semesterName;
  final String semesterCourseResultsUrl;
  final List<DualisModule> modules;

  DualisSemester(
    this.semesterName,
    this.semesterCourseResultsUrl,
    this.modules,
  );
}

class DualisModule {
  final String id;
  final String name;
  final String finalGrade;
  final String credits;
  final String detailsUrl;
  final ExamState state;

  DualisModule(
    this.id,
    this.name,
    this.finalGrade,
    this.credits,
    this.state,
    this.detailsUrl,
  );
}

class DualisExam {
  final String tryNr;
  final String moduleName;
  final String name;
  final String grade;
  final String semester;

  DualisExam(
    this.name,
    this.moduleName,
    this.grade,
    this.tryNr,
    this.semester,
  );
}
