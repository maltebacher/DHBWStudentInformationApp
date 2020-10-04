import 'package:dhbwstudentapp/common/util/string_utils.dart';
import 'package:dhbwstudentapp/dualis/service/parsing/parsing_utils.dart';
import 'package:dhbwstudentapp/schedule/model/schedule.dart';
import 'package:dhbwstudentapp/schedule/model/schedule_entry.dart';
import 'package:dhbwstudentapp/schedule/model/schedule_query_result.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';

class RaplaResponseParser {
  static const String WEEK_BLOCK_CLASS = "week_block";
  static const String TOOLTIP_CLASS = "tooltip";
  static const String INFOTABLE_CLASS = "infotable";
  static const String RESOURCE_CLASS = "resource";
  static const String LABEL_CLASS = "label";
  static const String VALUE_CLASS = "value";
  static const String CLASS_NAME_LABEL = "Veranstaltungsname:";
  static const String CLASS_TITLE_LABEL = "Titel:";
  static const String PROFESSOR_NAME_LABEL = "Personen:";
  static const String DETAILS_LABEL = "Bemerkung:";

  static const Map<String, ScheduleEntryType> entryTypeMapping = {
    "Feiertag": ScheduleEntryType.PublicHoliday,
    "Online-Format (ohne Raumbelegung)": ScheduleEntryType.Online,
    "Vorlesung / Lehrbetrieb": ScheduleEntryType.Class,
    "Lehrveranstaltung": ScheduleEntryType.Class,
    "Klausur / Prüfung": ScheduleEntryType.Exam,
    "Prüfung": ScheduleEntryType.Exam
  };

  ScheduleQueryResult parseSchedule(String responseBody) {
    var document = parse(responseBody);

    var dates = _readDatesFromHeadersOrThrow(document);

    var allRows = document.getElementsByTagName("tr");

    var allEntries = <ScheduleEntry>[];
    var parseErrors = <ParseError>[];

    for (var row in allRows) {
      var currentDayInWeekIndex = 0;
      for (var cell in row.children) {
        if (cell.localName != "td") continue;

        // Skip all spacer cells. They are only used for the alignment in the html page
        if (cell.classes.contains("week_number")) continue;
        if (cell.classes.contains("week_header")) continue;
        if (cell.classes.contains("week_smallseparatorcell")) continue;
        if (cell.classes.contains("week_smallseparatorcell_black")) continue;
        if (cell.classes.contains("week_emptycell_black")) continue;

        // The week_separatorcell and week_separatorcell_black cell types mark
        // the end of a column
        if (cell.classes.contains("week_separatorcell_black") ||
            cell.classes.contains("week_separatorcell")) {
          currentDayInWeekIndex = currentDayInWeekIndex + 1;
          continue;
        }

        assert(currentDayInWeekIndex < dates.length + 1);

        // The important information is inside a week_block cell
        if (cell.classes.contains("week_block")) {
          try {
            var entry = _extractScheduleEntryOrThrow(
              cell,
              dates[currentDayInWeekIndex],
            );

            allEntries.add(entry);
          } catch (exception, trace) {
            parseErrors.add(ParseError(exception, trace));
          }
        }
      }
    }

    allEntries.sort(
      (ScheduleEntry e1, ScheduleEntry e2) => e1?.start?.compareTo(e2?.start),
    );

    return ScheduleQueryResult(
      Schedule.fromList(allEntries),
      parseErrors,
    );
  }

  List<DateTime> _readDatesFromHeadersOrThrow(Document document) {
    var year = _readYearOrThrow(document);

    // The only reliable way to read the dates is the table header.
    // Some schedule entries contain the dates in the description but not
    // in every case.
    var weekHeaders = document.getElementsByClassName("week_header");
    var dates = <DateTime>[];

    for (var header in weekHeaders) {
      var dateString = header.text + year;

      try {
        var date = DateFormat("dd.MM.yyyy").parse(dateString.substring(3));
        dates.add(date);
      } catch (exception, trace) {
        throw ParseException.withInner(exception, trace);
      }
    }
    return dates;
  }

  String _readYearOrThrow(Document document) {
    // The only reliable way to read the year of this schedule is to parse the
    // selected year in the date selector
    var comboBoxes = document.getElementsByTagName("select");

    String year;
    for (var box in comboBoxes) {
      if (box.attributes.containsKey("name") &&
          box.attributes["name"] == "year") {
        var entries = box.getElementsByTagName("option");

        for (var entry in entries) {
          if (entry.attributes.containsKey("selected") &&
              entry.attributes["selected"] == "") {
            year = entry.text;

            break;
          }
        }

        break;
      }
    }

    if (year == null) {
      throw ElementNotFoundParseException("year");
    }

    return year;
  }

  ScheduleEntry _extractScheduleEntryOrThrow(Element value, DateTime date) {
    // The tooltip tag contains the most relevant information
    var tooltip = value.getElementsByClassName(TOOLTIP_CLASS);

    // The only reliable way to extract the time
    var timeAndClassName = value.getElementsByTagName("a");

    if (tooltip.isEmpty)
      throw ElementNotFoundParseException("tooltip container");

    if (timeAndClassName.isEmpty)
      throw ElementNotFoundParseException("time and date container");

    var start = _parseTime(timeAndClassName[0].text.substring(0, 5), date);
    var end = _parseTime(timeAndClassName[0].text.substring(7, 12), date);

    if (start == null || end == null)
      throw ElementNotFoundParseException("start and end date container");

    var title = "";
    var details = "";
    var professor = "";

    ScheduleEntryType type = _extractEntryType(tooltip);

    var infotable = tooltip[0].getElementsByClassName(INFOTABLE_CLASS);

    if (infotable.isEmpty)
      throw ElementNotFoundParseException("infotable container");

    Map<String, String> properties = _parsePropertiesTable(infotable[0]);
    title = properties[CLASS_NAME_LABEL] ?? properties[CLASS_TITLE_LABEL];
    professor = properties[PROFESSOR_NAME_LABEL];
    details = properties[DETAILS_LABEL];

    if (title == null) throw ElementNotFoundParseException("title");

    // Sometimes the entry type is not set correctly. When the title of a class
    // begins with "Online - " it implies that it is online
    // In this case remove the online prefix and set the type correctly
    if (title.startsWith("Online - ") && type == ScheduleEntryType.Class) {
      title = title.substring("Online - ".length);
      type = ScheduleEntryType.Online;
    }

    if (professor?.endsWith(",") ?? false) {
      professor = professor.substring(0, professor.length - 1);
    }

    var resource = _extractResources(value);

    var scheduleEntry = ScheduleEntry(
      start: start,
      end: end,
      title: trimAndEscapeString(title),
      details: trimAndEscapeString(details),
      professor: trimAndEscapeString(professor),
      type: type,
      room: trimAndEscapeString(resource),
    );
    return scheduleEntry;
  }

  ScheduleEntryType _extractEntryType(List<Element> tooltip) {
    if (tooltip.isEmpty) return ScheduleEntryType.Unknown;

    var strongTag = tooltip[0].getElementsByTagName("strong");
    if (strongTag.isEmpty) return ScheduleEntryType.Unknown;

    var typeString = strongTag[0].innerHtml;

    var type = ScheduleEntryType.Unknown;
    if (entryTypeMapping.containsKey(typeString)) {
      type = entryTypeMapping[typeString];
    }

    return type;
  }

  Map<String, String> _parsePropertiesTable(Element infotable) {
    var map = <String, String>{};
    var labels = infotable.getElementsByClassName(LABEL_CLASS);
    var values = infotable.getElementsByClassName(VALUE_CLASS);

    for (var i = 0; i < labels.length; i++) {
      map[labels[i].innerHtml] = values[i].innerHtml;
    }
    return map;
  }

  DateTime _parseTime(String timeString, DateTime date) {
    try {
      var time = DateFormat("HH:mm").parse(timeString.substring(0, 5));
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    } catch (e) {
      return null;
    }
  }

  String _extractResources(Element value) {
    var resources = value.getElementsByClassName(RESOURCE_CLASS);

    var resourcesList = <String>[];
    for (var resource in resources) {
      resourcesList.add(resource.innerHtml);
    }

    return concatStringList(resourcesList, ", ");
  }
}
