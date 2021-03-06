class ZCL_ADF_SERVICE_EVENTHUB definition
  public
  inheriting from ZCL_ADF_SERVICE
  final
  create public .

public section.

  methods SEND
    redefinition .
protected section.

  methods GET_SAS_TOKEN
    redefinition .
private section.
ENDCLASS.



CLASS ZCL_ADF_SERVICE_EVENTHUB IMPLEMENTATION.


method GET_SAS_TOKEN.
DATA : lv_string_to_sign       TYPE string,
           encoded_base_address    TYPE string,
           body_xstring            TYPE xstring,
           sign                    TYPE string,
           final_token             TYPE string,
           decoded                 TYPE xstring,
           conv                    TYPE REF TO cl_abap_conv_out_ce,
           conv_in                 TYPE REF TO cl_abap_conv_in_ce,
           format                  TYPE i,
           new_expiry              TYPE string,
           lv_sas_key              TYPE string,
           lv_expiry_time          TYPE string.
  get_epoch_time( RECEIVING rv_expiry_time =  lv_expiry_time ).
  format = 18.
  encoded_base_address = escape( val = iv_baseaddress format = format  ).
  CONCATENATE encoded_base_address  cl_abap_char_utilities=>newline lv_expiry_time INTO lv_string_to_sign.

  conv = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
  conv->convert( EXPORTING data = lv_string_to_sign IMPORTING buffer = body_xstring ).
  DEFINE encrypt_key.
    decode_sign( receiving rv_secret = lv_sas_key ).
    conv = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
    conv->convert( exporting data = lv_sas_key importing buffer = decoded ).

    call method cl_abap_hmac=>calculate_hmac_for_raw
      exporting
        if_algorithm     = 'sha-256'
        if_key           = decoded
        if_data          = body_xstring
        if_length        = 0
      importing
        ef_hmacb64string = sign.
    clear : lv_sas_key, decoded.
  END-OF-DEFINITION.
  encrypt_key.
  new_expiry = lv_expiry_time.
  CONDENSE new_expiry.
  IF NOT sign IS INITIAL.
    data wa_policy type zadf_ehub_policy.
    SELECT SINGLE * FROM zadf_ehub_policy into wa_policy WHERE interface_id EQ  gv_interface_id.
    sign = escape( val = sign format = format  ).
    CONCATENATE 'SharedAccessSignature sr=' encoded_base_address  '&sig=' sign '&se=' new_expiry '&skn=' wa_policy-policy INTO final_token.
    rv_sas_token = final_token.
  ELSE.
    RAISE EXCEPTION TYPE zcx_adf_service
      EXPORTING
        textid       = zcx_adf_service=>sas_key_not_generated
        interface_id = gv_interface_id.
  ENDIF.
endmethod.


method SEND.
  DATA : lo_response     TYPE REF TO if_rest_entity,
           lo_request      TYPE REF TO if_rest_entity,
           lv_expiry       TYPE string,
           lv_sas_token    TYPE string,
           lv_msg          TYPE string,
           lcx_adf_service TYPE REF TO zcx_adf_service.
  IF go_rest_api IS BOUND.
    TRY.
        get_sas_token( EXPORTING iv_baseaddress = gv_uri
                       RECEIVING rv_sas_token  = lv_sas_token ).
      CATCH zcx_adf_service INTO lcx_adf_service.
        lv_msg =  lcx_adf_service->get_text( ).
        MESSAGE lv_msg TYPE 'I'.
    ENDTRY.
*   Set the path prefix from the headers instead of creating many RFC
    DATA  : wa_headers TYPE ihttpnvp , lt_headers LIKE it_headers.
    lt_headers[] = it_headers[].
    LOOP AT lt_headers INTO wa_headers.
      IF wa_headers-name = 'path_prefix'.
        go_rest_api->zif_rest_framework~set_uri( wa_headers-value ).
      ENDIF.
    ENDLOOP.
    DELETE lt_headers WHERE name EQ 'path_prefix'.

*   Add custom headers.
    add_request_header( iv_name = 'Content-Type' iv_value = 'application/json; charset=utf-8' ).
    add_request_header( iv_name = 'Authorization' iv_value = lv_sas_token ).
    go_rest_api->zif_rest_framework~set_binary_body( request ).
    IF NOT it_headers[] IS INITIAL.
      go_rest_api->zif_rest_framework~set_request_headers( it_header_fields = lt_headers[] ).
    ENDIF.
**Rest API call to get response from Azure Destination
    lo_response = go_rest_api->zif_rest_framework~execute( io_entity = lo_request async = gv_asynchronous is_retry = gv_is_try ).
    ev_http_status = go_rest_api->get_status( ).
    go_rest_api->close( ).
    IF lo_response IS BOUND.
      response = lo_response->get_string_data( ).
    ELSE.
      RAISE EXCEPTION TYPE zcx_adf_service
        EXPORTING
          textid       = zcx_adf_service=>restapi_response_not_found
          interface_id = gv_interface_id.
    ENDIF.
  ENDIF.
endmethod.
ENDCLASS.
