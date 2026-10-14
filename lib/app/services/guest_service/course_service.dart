import 'dart:convert';
import 'dart:developer';

import 'package:webinar/app/models/content_model.dart';
import 'package:webinar/app/models/course_model.dart';
import 'package:webinar/app/models/notice_model.dart';
import 'package:webinar/app/models/single_course_model.dart';
import 'package:webinar/app/models/user_model.dart';
import 'package:webinar/common/data/api_public_data.dart';
import 'package:webinar/common/utils/app_text.dart';
import 'package:webinar/common/utils/constants.dart';
import 'package:http/http.dart';
import 'package:webinar/common/utils/http_handler.dart';

import '../../../common/enums/error_enum.dart';
import '../../../common/utils/error_handler.dart';
import '../../../common/components.dart';
import '../../models/single_content_model.dart';
import '../authentication_service/authentication_service.dart';
import 'categories_service.dart';

class CourseService{

  static List<CourseModel> _coursesFromDynamic(dynamic data) {
    final list = <CourseModel>[];
    if (data == null) return list;

    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          list.add(CourseModel.fromJson(item));
        } else if (item is Map) {
          list.add(CourseModel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    }

    if (data is Map) {
      final nested = data['webinars'] ?? data['courses'];
      if (nested != null) {
        return _coursesFromDynamic(nested);
      }
    }

    return list;
  }

  static String _appendCourseListQuery(
    String url, {
    bool upcoming = false,
    bool free = false,
    bool discount = false,
    bool downloadable = false,
    String? sort,
    bool reward = false,
    List<int>? filterOption,
  }) {
    if (upcoming) url += '&upcoming=1';
    if (free) url += '&free=1';
    if (discount) url += '&discount=1';
    if (downloadable) url += '&downloadable=1';
    if (reward) url += '&reward=1';
    if (sort != null) url += '&sort=$sort';
    if (filterOption != null && filterOption.isNotEmpty) {
      for (final id in filterOption) {
        url += '&filter_option=$id';
      }
    }
    return url;
  }

  static List<CourseModel> _applyClientCourseFilters(
    List<CourseModel> items, {
    bool free = false,
    bool discount = false,
    bool reward = false,
    String? sort,
    required int offset,
    int limit = 10,
  }) {
    var filtered = List<CourseModel>.from(items);

    if (free) {
      filtered = filtered.where((c) => (c.price ?? 0) == 0).toList();
    }
    if (discount) {
      filtered = filtered.where((c) => (c.discountPercent ?? 0) > 0).toList();
    }
    if (reward) {
      filtered = filtered.where((c) => (c.points ?? 0) > 0).toList();
    }

    switch (sort) {
      case 'newest':
        filtered.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
        break;
      case 'best_rates':
        filtered.sort((a, b) {
          final ar = double.tryParse(a.rate ?? '0') ?? 0;
          final br = double.tryParse(b.rate ?? '0') ?? 0;
          return br.compareTo(ar);
        });
        break;
      case 'bestsellers':
        filtered.sort((a, b) => (b.salesCountNumber ?? 0).compareTo(a.salesCountNumber ?? 0));
        break;
    }

    if (offset >= filtered.length) return [];
    final end = (offset + limit).clamp(0, filtered.length);
    return filtered.sublist(offset, end);
  }

  static Future<List<CourseModel>> _getFromCategoryWebinars({
    required int categoryId,
    required int offset,
    int limit = 10,
    bool upcoming = false,
    bool free = false,
    bool discount = false,
    bool downloadable = false,
    String? sort,
    bool reward = false,
    List<int>? filterOption,
  }) async {
    try {
      var url =
          '${Constants.baseUrl}categories/$categoryId/webinars?offset=$offset&limit=$limit';
      url = _appendCourseListQuery(
        url,
        upcoming: upcoming,
        free: free,
        discount: discount,
        downloadable: downloadable,
        sort: sort,
        reward: reward,
        filterOption: filterOption,
      );

      final res = await httpGet(url, isMaintenance: true);
      final jsonRes = parseCleanJson(res.body.toString());
      if (jsonRes['success'] == true) {
        return _coursesFromDynamic(jsonRes['data']);
      }
    } catch (_) {}
    return [];
  }

  /// When `/courses` returns empty, collect webinars from category endpoints (Rocket LMS).
  static Future<List<CourseModel>> _discoverCoursesAcrossCategories({
    required int offset,
    int limit = 10,
    bool upcoming = false,
    bool free = false,
    bool discount = false,
    bool downloadable = false,
    String? sort,
    bool reward = false,
    List<int>? filterOption,
  }) async {
    final categories = await CategoriesService.categories();
    final merged = <CourseModel>[];
    final seenIds = <int>{};

    for (final category in categories) {
      if (category.id == null) continue;
      final chunk = await _getFromCategoryWebinars(
        categoryId: category.id!,
        offset: 0,
        limit: 50,
        upcoming: upcoming,
        free: free,
        discount: discount,
        downloadable: downloadable,
        sort: sort,
        reward: reward,
        filterOption: filterOption,
      );
      for (final course in chunk) {
        final id = course.id;
        if (id != null && seenIds.add(id)) {
          merged.add(course);
        }
      }
    }

    return _applyClientCourseFilters(
      merged,
      free: free,
      discount: discount,
      reward: reward,
      sort: sort,
      offset: offset,
      limit: limit,
    );
  }

  static Future<List<CourseModel>> getAll({ required int offset,bool upcoming=false, bool free=false, bool discount=false, bool downloadable=false, String? sort, String? type, String? cat, bool reward=false, bool bundle=false, List<int>? filterOption, })async{
    List<CourseModel> data = [];
    try{
      if (!bundle && cat != null) {
        final categoryId = int.tryParse(cat);
        if (categoryId != null) {
          data = await _getFromCategoryWebinars(
            categoryId: categoryId,
            offset: offset,
            limit: 10,
            upcoming: upcoming,
            free: free,
            discount: discount,
            downloadable: downloadable,
            sort: sort,
            reward: reward,
            filterOption: filterOption,
          );
          if (data.isNotEmpty) {
            log('course count (category webinars): ${data.length}');
            return data;
          }
        }
      }

      String url = '${Constants.baseUrl}${bundle ? 'bundles' : 'courses'}?offset=$offset&limit=10';
      url = _appendCourseListQuery(
        url,
        upcoming: upcoming,
        free: free,
        discount: discount,
        downloadable: downloadable,
        sort: sort,
        reward: reward,
        filterOption: filterOption,
      );
      if (cat != null) url += '&cat=$cat';

      Response res = await httpGet(url);
        
      var jsonRes = parseCleanJson(res.body.toString());
      

      if (jsonRes['success'] ?? false) {

        if(bundle){
          final bundles = jsonRes['data']?['bundles'];
          if (bundles is List) {
            for (final json in bundles) {
              if (json is Map<String, dynamic>) {
                data.add(CourseModel.fromJson(json));
              } else if (json is Map) {
                data.add(CourseModel.fromJson(Map<String, dynamic>.from(json)));
              }
            }
          }

        }else{
          data = _coursesFromDynamic(jsonRes['data']);
        }

        if (!bundle && data.isEmpty && offset == 0) {
          data = await _discoverCoursesAcrossCategories(
            offset: offset,
            limit: 10,
            upcoming: upcoming,
            free: free,
            discount: discount,
            downloadable: downloadable,
            sort: sort,
            reward: reward,
            filterOption: filterOption,
          );
        }

        log('course count : ${data.length}');
        return data;
      }else{
        return data;
      }

    }catch(e){
      return data;
    }
  }


  static Future<SingleCourseModel?> getOverviewCourseData(int id,bool isBundle,{bool isPrivate=false})async{
    try{

      String url = '${Constants.baseUrl}${isPrivate ? 'panel/webinars' : isBundle ? 'panel/bundles' : 'panel/webinars'}/$id';

      Response res = await httpGet(
        url,
        isSendToken: true
      );
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success'] ?? false) {
        return SingleCourseModel.fromJson( 
          isBundle 
            ? jsonRes['data']['bundle'] 
            : jsonRes['data']
        );
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonRes, readMessage: true);
        return null;
      }


    }catch(e){
      return null;
    }
  }

  static Future<SingleCourseModel?> getSingleCourseData(int id,bool isBundle,{bool isPrivate=false})async{
    try{

      String url = '${Constants.baseUrl}${isPrivate ? 'panel/webinars' : isBundle ? 'bundles' : 'courses'}/$id';

      Response res = await httpGet(
        url,
        isSendToken: true
      );
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success'] ?? false) {
        return SingleCourseModel.fromJson( 
          isBundle 
            ? jsonRes['data']['bundle'] 
            : jsonRes['data']
        );
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonRes, readMessage: true);
        return null;
      }


    }catch(e){
      showSnackBar(ErrorEnum.error, null, desc: appText.serverExceptionError);
      return null;
    }
  }

  static Future<List<CourseModel>> featuredCourse({String? cat,})async{
    List<CourseModel> data = [];
    try{

      String url = '${Constants.baseUrl}featured-courses';

      if(cat != null) url += '?cat=$cat';

      Response res = await httpGet(url, isMaintenance: true);

      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success'] == true) {
        data = _coursesFromDynamic(jsonRes['data']);
        if (data.isNotEmpty) {
          log('featured course count : ${data.length}');
          return data;
        }
      }

      if (cat != null) {
        final categoryId = int.tryParse(cat);
        if (categoryId != null) {
          data = await _getFromCategoryWebinars(
            categoryId: categoryId,
            offset: 0,
            limit: 10,
          );
        }
      } else {
        data = await _discoverCoursesAcrossCategories(offset: 0, limit: 10);
      }

      log('featured course count (fallback): ${data.length}');
      return data.take(10).toList();

    }catch(e){
      return data;
    }
  }
  

  static Future<List<CourseModel>> getBundleWebinars(int bundleId)async{
    List<CourseModel> data = [];
    try{

      String url = '${Constants.baseUrl}bundles/$bundleId/webinars';


      Response res = await httpGet(url, isMaintenance: true);
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success']) {
        jsonRes['data']['webinars'].forEach((json){
          data.add(CourseModel.fromJson(json));
        });

        return data;
      }else{
        return data;
      }


    }catch(e){
      return data;
    }
  }
  
  static Future<List<CourseModel>> bundleCourses(int bundleId)async{
    List<CourseModel> data = [];
    try{

      String url = '${Constants.baseUrl}bundles/$bundleId/webinars';



      Response res = await httpGet(url);
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success']) {
        jsonRes['data']['webinars'].forEach((json){
          data.add(CourseModel.fromJson(json));
        });

        log('featured course count : ${data.length}');
        return data;
      }else{
        return data;
      }


    }catch(e){
      return data;
    }
  }

  static Future<List<String>> getReasons()async{
    List<String> data = [];
    try{

      String url = '${Constants.baseUrl}courses/reports/reasons';




      Response res = await httpGet(url);
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success']) {
        jsonRes['data'].forEach((json){
          data.add(json);
        });

        PublicData.reasonsData = data;

        return data;
      }else{
        return data;
      }


    }catch(e){
      return data;
    }
  }

  static Future<List<NoticeModel>> getNotices(int id)async{
    List<NoticeModel> data = [];
    try{

      String url = '${Constants.baseUrl}panel/webinars/$id/noticeboards';




      Response res = await httpGetWithToken(url);
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success']) {
        jsonRes['data'].forEach((json){
          data.add(NoticeModel.fromJson(json));
        });


        return data;
      }else{
        return data;
      }


    }catch(e){
      return data;
    }
  }

  static Future<bool> reportCourse(String reason,int courseId,String message)async{
   
    try{

      String url = '${Constants.baseUrl}courses/$courseId/report';


      Response res = await httpPostWithToken(
        url,
        {
          "reason" : reason,
          "message" : message
        }
      );
        
      var jsonResponse = parseCleanJson(res.body.toString());

      if(jsonResponse['success']){
        showSnackBar(ErrorEnum.success, jsonResponse['message']?.toString());
        return true;
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return false;
      }


    }catch(e){
      return false;
    }
  }

  static Future<bool> toggle(int courseId,String itemName,String itemId,bool status)async{
   
    try{

      String url = '${Constants.baseUrl}courses/$courseId/toggle';


      Response res = await httpPostWithToken(
        url,
        {
          "item" : itemName,
          "item_id" : itemId,
          "status" : status
        }
      );
        
      var jsonResponse = parseCleanJson(res.body.toString());
      print(jsonResponse);

      if(jsonResponse['success']){
        return true;
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return false;
      }


    }catch(e){
      return false;
    }
  }

  static Future<bool> addFavorite(int courseId, bool isBundle)async{
   
    try{

      String url = '${Constants.baseUrl}panel/favorites/toggle2';

      Response res = await httpPostWithToken(
        url,
        {
          "item" : isBundle ? 'bundle' : 'webinar',
          "id" : courseId
        }
      );
        
      var jsonResponse = parseCleanJson(res.body.toString());

      if(jsonResponse['success']){
        ErrorHandler().showError(ErrorEnum.success, jsonResponse, readMessage: true);
        return true;
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse, readMessage: true);
        return false;
      }


    }catch(e){
      return false;
    }
  }

  static Future<(List<CourseModel> courseData, List<UserModel> usersData, List<UserModel> organizationsData)> search(String text)async{
    List<CourseModel> courseData = [];
    List<UserModel> usersData = [];
    List<UserModel> organizationsData = [];

    try{

      String url = '${Constants.baseUrl}search?search=$text';



      Response res = await httpGet(url);
        
      var jsonRes = parseCleanJson(res.body.toString());

      if (jsonRes['success']) {
        
        jsonRes['data']['webinars']['webinars'].forEach((json){
          courseData.add(CourseModel.fromJson(json));
        });
        
        jsonRes['data']['users']['users'].forEach((json){
          usersData.add(UserModel.fromJson(json));
        });
        
        jsonRes['data']['organizations']['organizations'].forEach((json){
          organizationsData.add(UserModel.fromJson(json));
        });

        return (courseData,usersData,organizationsData);
      }else{
        return (courseData,usersData,organizationsData);
      }


    }catch(e){
      return (courseData,usersData,organizationsData);
    }
  }



  static Future<List<ContentModel>> getContent(int courseId) async {
    List<ContentModel> data = [];

    try{
      String url = '${Constants.baseUrl}courses/$courseId/content';

      Response res = await httpGetWithToken(
        url, 
        isRedirectingStatusCode: false
      );


      var jsonResponse = parseCleanJson(res.body.toString());


      if(jsonResponse['success']){

        jsonResponse['data'].forEach((json){
          data.add(ContentModel.fromJson(json));
        });

        return data;
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return data;
      }

    }catch(e){
      return data;
    }
  }

  static Future<String?> getContentJSON(int courseId) async {

    try{
      String url = '${Constants.baseUrl}courses/$courseId/content';

      Response res = await httpGetWithToken(
        url, 
        isRedirectingStatusCode: false
      );

      var jsonResponse = parseCleanJson(res.body.toString());

      if(jsonResponse['success']){
        return jsonEncode(jsonResponse['data'] ?? {});
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return null;
      }

    }catch(e){
      return null;
    }
  }



  static Future<SingleContentModel?> getSingleContent(String url) async {

    try{

      Response res = await httpGetWithToken(
        url, 
        isRedirectingStatusCode: false
      );

      var jsonResponse = parseCleanJson(res.body.toString());

      if(jsonResponse['success'] ?? false){

        return SingleContentModel.fromJson(jsonResponse['data']);
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return null;
      }

    }catch(e){
      return null;
    }
  }

  static Future<String?> getSingleContentJSON(String url) async {

    try{

      Response res = await httpGetWithToken(
        url, 
        isRedirectingStatusCode: false
      );


      var jsonResponse = parseCleanJson(res.body.toString());

      if(jsonResponse['success'] ?? false){

        return res.body;
      }else{
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return null;
      }

    }catch(e){
      return null;
    }
  }

}