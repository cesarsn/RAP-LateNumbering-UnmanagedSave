CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS GetDefaultsForBookings FOR READ
      IMPORTING keys FOR FUNCTION Travel~GetDefaultsForBookings RESULT result.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.

  METHOD get_instance_authorizations.
    "To-do: Implement instance authorization
  ENDMETHOD.

  METHOD GetDefaultsForBookings.

    "This method will default the id of the new booking by reading all the bookings of
    "the travel and incrementing the highest id by 1.
    "Also, the booking date is set to the current system date.
    DATA: lt_read_keys TYPE TABLE FOR READ IMPORT ZI_Travel_U_CSN\\Travel\_Booking,
          ls_read_key  LIKE LINE OF lt_read_keys,
          ls_result    LIKE LINE OF result.
    DATA: lv_new_booking_id TYPE /dmo/booking_id.

    LOOP AT keys INTO DATA(ls_key).
      ls_read_key-%tky = ls_key-%tky.   "%TKY includes %is_draft, %pid and TravelId
      INSERT ls_read_key INTO TABLE lt_read_keys.
    ENDLOOP.

    READ ENTITIES OF ZI_Travel_U_CSN IN LOCAL MODE
        ENTITY Travel BY \_Booking
           FIELDS ( TravelID BookingId )
           WITH lt_read_keys
           RESULT DATA(lt_bookings).

    SORT lt_bookings BY %is_draft %pidparent TravelId BookingId DESCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_bookings COMPARING %is_draft %pidparent TravelId.

    LOOP AT keys INTO ls_key.
      CLEAR: ls_result, lv_new_booking_id.
      TRY.
          DATA(ls_booking) = lt_bookings[ KEY entity %is_draft = ls_key-%is_draft %pidparent = ls_key-%pid TravelId = ls_key-TravelID ].
          lv_new_booking_id = ls_booking-BookingID + 1.
        CATCH cx_root.
          lv_new_booking_id = 1.
      ENDTRY.
      ls_result-%tky = ls_key-%tky.
      ls_result-%param-TravelID    = ls_key-TravelID.
      ls_result-%param-BookingID   = lv_new_booking_id.
      ls_result-%param-BookingDate = cl_abap_context_info=>get_system_date( ).
      INSERT ls_result INTO TABLE result.
    ENDLOOP.



  ENDMETHOD.

ENDCLASS.

CLASS lsc_ZI_TRAVEL_U_CSN DEFINITION INHERITING FROM cl_abap_behavior_saver_failed.
  PROTECTED SECTION.
    TYPES: BEGIN OF ts_key,
             travelid      TYPE /dmo/travel_id,
             delete_entity TYPE abap_boolean,
           END OF ts_key,
           tt_keys TYPE STANDARD TABLE OF ts_key WITH DEFAULT KEY.

    METHODS adjust_numbers REDEFINITION.

    METHODS save_modified REDEFINITION.

    METHODS cleanup_finalize REDEFINITION.
  PRIVATE SECTION.
    TYPES: ts_read_result_travel  TYPE STRUCTURE FOR READ RESULT zi_travel_u_csn,
           ts_read_result_booking TYPE TABLE FOR READ RESULT zi_booking_u_csn,
           ts_failed              TYPE RESPONSE FOR FAILED LATE zi_travel_u_csn,
           ts_reported            TYPE RESPONSE FOR REPORTED LATE zi_travel_u_csn,
           ts_mapped              TYPE RESPONSE FOR MAPPED LATE zi_travel_u_csn,
           ts_request_change      TYPE REQUEST FOR CHANGE zi_travel_u_csn,
           ts_request_delete      TYPE REQUEST FOR DELETE zi_travel_u_csn.

    METHODS _add_deleted_bookings
      IMPORTING
        is_key      TYPE lsc_zi_travel_u_csn=>ts_key
        delete      TYPE ts_request_delete
      CHANGING
        ct_booking  TYPE /dmo/t_booking_in
        ct_bookingx TYPE /dmo/t_booking_inx.


    METHODS _add_updated_bookings
      IMPORTING
        is_key      TYPE lsc_zi_travel_u_csn=>ts_key
        update      TYPE ts_request_change
      CHANGING
        ct_booking  TYPE /dmo/t_booking_in
        ct_bookingx TYPE /dmo/t_booking_inx.


    METHODS _add_new_bookings
      IMPORTING
        is_key      TYPE lsc_zi_travel_u_csn=>ts_key
        create      TYPE ts_request_change
      CHANGING
        ct_booking  TYPE /dmo/t_booking_in
        ct_bookingx TYPE /dmo/t_booking_inx.

    METHODS _process_key
      IMPORTING
        is_key   TYPE lsc_zi_travel_u_csn=>ts_key
        create   TYPE ts_request_change
        update   TYPE ts_request_change
        delete   TYPE ts_request_delete
      CHANGING
        failed   TYPE ts_failed
        reported TYPE ts_reported.

    METHODS _delete_travel
      IMPORTING
        is_key      TYPE lsc_zi_travel_u_csn=>ts_key
      EXPORTING
        et_messages TYPE /dmo/t_message.

    METHODS _update_travel
      IMPORTING
        is_key      TYPE lsc_zi_travel_u_csn=>ts_key
        create      TYPE ts_request_change
        update      TYPE ts_request_change
        delete      TYPE ts_request_delete
      EXPORTING
        et_messages TYPE /dmo/t_message.

    METHODS _get_processed_root_keys
      IMPORTING
        create          TYPE ts_request_change
        update          TYPE ts_request_change
        delete          TYPE ts_request_delete
      RETURNING
        VALUE(r_result) TYPE lsc_zi_travel_u_csn=>tt_keys.

    METHODS _create_travel
      IMPORTING
        is_travel    TYPE ts_read_result_travel
        it_bookings  TYPE ts_read_result_booking
      EXPORTING
        ev_travel_id TYPE /dmo/travel_id
      CHANGING
        failed       TYPE ts_failed
        reported     TYPE ts_reported
        mapped       TYPE ts_mapped.

ENDCLASS.

CLASS lsc_ZI_TRAVEL_U_CSN IMPLEMENTATION.

  METHOD adjust_numbers.
    "Create processing logic to adjust numbers if needed
    "Read travel and booking data from buffer, call the API function and
    "create travel

    "Two create options:
    "1.- Create a new travel (with bookings)
    "2.- Crate a new booking for a existing travel

    DATA: lt_travel_key TYPE TABLE FOR READ IMPORT ZI_Travel_U_CSN\\Travel.
    DATA: lt_booking_key TYPE TABLE FOR READ IMPORT ZI_Travel_U_CSN\\Booking.

    "Process only if there are changes
    CHECK mapped-travel IS NOT INITIAL OR mapped-booking IS NOT INITIAL.

    "Read operation is done with %PID, %TMP-TRAVELID (this is initial for new travels)
    LOOP AT mapped-travel INTO DATA(ls_mapped_travel).
      INSERT VALUE #( %pid = ls_mapped_travel-%pid %key = ls_mapped_travel-%tmp ) INTO TABLE lt_travel_key.
    ENDLOOP.
    "Read operation is done with %PID, %TMP-TRAVELID, %TMP-BOOKINGID
    LOOP AT mapped-booking INTO DATA(ls_mapped_booking).
      INSERT VALUE #( %pid = ls_mapped_booking-%pid %key = ls_mapped_booking-%tmp ) INTO TABLE lt_booking_key.
    ENDLOOP.

    READ ENTITIES OF ZI_Travel_U_CSN IN LOCAL MODE
        ENTITY Travel
           ALL FIELDS WITH CORRESPONDING #( lt_travel_key )
           RESULT DATA(lt_all_travels).

    READ ENTITIES OF ZI_Travel_U_CSN IN LOCAL MODE
        ENTITY Booking
           ALL FIELDS WITH CORRESPONDING #( lt_booking_key )
           RESULT DATA(lt_all_bookings).


    "Create travel with bookings (case 1)
    LOOP AT lt_all_travels INTO DATA(ls_travel).
      DATA(lt_bookings) = lt_all_bookings.
      DELETE lt_bookings WHERE %pidparent <> ls_travel-%pid.
      _create_travel(
        EXPORTING
          is_travel      = ls_travel
          it_bookings    = lt_bookings
        IMPORTING
          ev_travel_id   = ls_travel-TravelID
        CHANGING
          failed         = failed
          reported       = reported
          mapped         = mapped
      ).

    ENDLOOP.

    "Assign pending booking id from preliminay identifiers. Take into account that this values
    "are assigned during interaction phase
    "At this point, we will assign new bookings ids for existing travels (case 2)
    LOOP AT mapped-booking ASSIGNING FIELD-SYMBOL(<fs_booking>)
    WHERE bookingid IS INITIAL AND
          %tmp-TravelID IS NOT INITIAL AND
          %tmp-BookingID IS NOT INITIAL.
      <fs_booking>-TravelID  = <fs_booking>-%tmp-TravelID.
      <fs_booking>-Bookingid = <fs_booking>-%tmp-Bookingid.
    ENDLOOP.

  ENDMETHOD.

  METHOD save_modified.
    "Update processing logic to save modified data
    "Process only updated travels. Created travels are processed in adjust_numbers method

    DATA: lt_processed_keys TYPE tt_keys.


    lt_processed_keys = _get_processed_root_keys( create = create
                                                  update = update
                                                  delete = delete ).

    LOOP AT lt_processed_keys INTO DATA(ls_key).
      _process_key( EXPORTING is_key = ls_key
                               create = create
                               update = update
                               delete = delete
                     CHANGING  failed   = failed
                               reported = reported ).
    ENDLOOP.




  ENDMETHOD.

  METHOD cleanup_finalize.
    "Not required
  ENDMETHOD.


  METHOD _create_travel.

    "Call /DMO/FLIGHT_TRABEL_CREATE function to create travel and bookings
    "Take into account that this API requires two calls: 1 for create and 1 for save (persist data in database)

    DATA: ls_travel_out  TYPE /dmo/travel,
          ls_travel_in   TYPE /dmo/s_travel_in,
          ls_booking_in  TYPE /dmo/s_booking_in,
          lt_bookings_in TYPE /dmo/t_booking_in,
          lt_messages    TYPE /dmo/t_message.

    "Initialize buffers
    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_INITIALIZE'.

    ls_travel_in = CORRESPONDING #( is_travel MAPPING FROM ENTITY ).
    LOOP AT it_bookings INTO DATA(ls_booking).
      CLEAR: ls_booking_in.
      ls_booking_in = CORRESPONDING #( ls_booking MAPPING FROM ENTITY ).
      INSERT ls_booking_in INTO TABLE lt_bookings_in.
    ENDLOOP.

    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_CREATE'
      EXPORTING
        is_travel   = ls_travel_in
        it_booking  = lt_bookings_in
      IMPORTING
        es_travel   = ls_travel_out
        et_messages = lt_messages.

    "Map errors as failed
    DELETE lt_messages WHERE msgty NA 'EAX'.

    IF lt_messages[] IS NOT INITIAL.
      LOOP AT lt_messages INTO DATA(ls_message).
        INSERT VALUE #( %tky = is_travel-%tky
                        %msg = new_message( id       = ls_message-msgid
                                            severity = if_abap_behv_message=>severity-error
                                            number   = ls_message-msgno
                                            v1       = ls_message-msgv1
                                            v2       = ls_message-msgv2
                                            v3       = ls_message-msgv3
                                            v4       = ls_message-msgv4 )
                        ) INTO TABLE reported-travel.
      ENDLOOP.
      INSERT VALUE #( %tky = is_travel-%tky ) INTO TABLE failed-travel.
      RETURN.
    ENDIF.

    "Save to database
    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_SAVE'.

    "Map final ids
    "Travel
    READ TABLE mapped-travel ASSIGNING FIELD-SYMBOL(<fs_mapped_travel>)
      WITH KEY id COMPONENTS %pid = is_travel-%pid.
    <fs_mapped_travel>-TravelID = ls_travel_out-travel_id.

    "Bookings for this travel
    LOOP AT it_bookings ASSIGNING FIELD-SYMBOL(<fs_booking>)
      WHERE %pidparent = is_travel-%pid.
      "Map booking id
      READ TABLE mapped-booking ASSIGNING FIELD-SYMBOL(<fs_mapped_booking>)
        WITH KEY id COMPONENTS %pid = <fs_booking>-%pid.
      <fs_mapped_booking>-BookingId = <fs_booking>-BookingId.
      <fs_mapped_booking>-TravelID  = ls_travel_out-travel_id.
    ENDLOOP.

  ENDMETHOD.


  METHOD _get_processed_root_keys.

    LOOP AT create-booking INTO DATA(ls_booking).
      INSERT VALUE #( travelid = ls_booking-TravelID ) INTO TABLE r_result.
    ENDLOOP.

    LOOP AT update-booking INTO ls_booking.
      INSERT VALUE #( travelid = ls_booking-TravelID ) INTO TABLE r_result.
    ENDLOOP.

    LOOP AT update-travel INTO DATA(ls_travel).
      INSERT VALUE #( travelid = ls_travel-TravelID ) INTO TABLE r_result.
    ENDLOOP.

    LOOP AT delete-travel INTO DATA(ls_delete_travel).
      INSERT VALUE #( travelid = ls_delete_travel-TravelID delete_entity = abap_true ) INTO TABLE r_result.
    ENDLOOP.

    LOOP AT delete-booking INTO DATA(ls_delete_booking).
      INSERT VALUE #( travelid = ls_delete_booking-TravelID ) INTO TABLE r_result.
    ENDLOOP.

    "Discard created travels as they are processed in adjust_numbers method
    LOOP AT create-travel INTO ls_travel.
      DELETE r_result WHERE travelid = ls_travel-TravelID.
    ENDLOOP.

    SORT r_result BY travelid delete_entity DESCENDING.
    DELETE ADJACENT DUPLICATES FROM r_result COMPARING travelid.


  ENDMETHOD.


  METHOD _update_travel.


    DATA: ls_travel   TYPE /dmo/s_travel_in,
          ls_travelx  TYPE /dmo/s_travel_inx,
          lt_booking  TYPE /dmo/t_booking_in,
          lt_bookingx TYPE /dmo/t_booking_inx.

    "Updated value for travel?
    TRY.
        DATA(ls_update_travel) = update-travel[ KEY id TravelID = is_key-travelid ].
        ls_travel = CORRESPONDING #( ls_update_travel MAPPING FROM ENTITY ).
        ls_travelx = CORRESPONDING #(  CORRESPONDING /dmo/s_travel_intx( ls_update_travel MAPPING FROM ENTITY USING CONTROL ) ).
      CATCH cx_root.
    ENDTRY.
    ls_travel-travel_id = is_key-travelid.
    ls_travelx-travel_id = is_key-travelid.
    "Bookings created
    _add_new_bookings( EXPORTING is_key = is_key
                                 create = create
                      CHANGING
                        ct_booking = lt_booking
                        ct_bookingx = lt_bookingx ).

    "Bookings updated
    _add_updated_bookings( EXPORTING is_key = is_key
                                 update = update
                      CHANGING
                        ct_booking = lt_booking
                        ct_bookingx = lt_bookingx ).


    "Bookings deleted
    _add_deleted_bookings( EXPORTING is_key = is_key
                                 delete = delete
                      CHANGING
                        ct_booking = lt_booking
                        ct_bookingx = lt_bookingx ).

    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_UPDATE'
      EXPORTING
        is_travel   = ls_travel
        is_travelx  = ls_travelx
        it_booking  = lt_booking
        it_bookingx = lt_bookingx
      IMPORTING
        et_messages = et_messages.

  ENDMETHOD.


  METHOD _delete_travel.

    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_DELETE'
      EXPORTING
        iv_travel_id = is_key-travelid
      IMPORTING
        et_messages  = et_messages.

  ENDMETHOD.


  METHOD _process_key.

    DATA: lt_messages TYPE /dmo/t_message.

    "Initialize buffers
    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_INITIALIZE'.

    IF is_key-delete_entity = abap_true.
      _delete_travel( EXPORTING is_key = is_key
                          IMPORTING et_messages = lt_messages ).
    ELSE.
      _update_travel( EXPORTING is_key = is_key
                                    create = create
                                    update = update
                                    delete = delete
                          IMPORTING et_messages = lt_messages ).
    ENDIF.

    DELETE lt_messages WHERE msgty NA 'EAX'.
    IF lt_messages[] IS NOT INITIAL.
      LOOP AT lt_messages INTO DATA(ls_message).
        INSERT VALUE #( travelid = is_key-travelid
                        %msg = new_message( id       = ls_message-msgid
                                            severity = if_abap_behv_message=>severity-error
                                            number   = ls_message-msgno
                                            v1       = ls_message-msgv1
                                            v2       = ls_message-msgv2
                                            v3       = ls_message-msgv3
                                            v4       = ls_message-msgv4 )
                        ) INTO TABLE reported-travel.
      ENDLOOP.
      INSERT VALUE #( travelid = is_key-travelid ) INTO TABLE failed-travel.
      RETURN.
    ENDIF.

    "Save to database
    CALL FUNCTION '/DMO/FLIGHT_TRAVEL_SAVE'.



  ENDMETHOD.


  METHOD _add_new_bookings.

    DATA: ls_booking_in  TYPE /dmo/s_booking_in,
          ls_booking_inx TYPE /dmo/s_booking_inx.

    LOOP AT create-booking INTO DATA(ls_booking)
        USING KEY id WHERE TravelID = is_key-travelid.
      "Add new booking
      CLEAR: ls_booking_in, ls_booking_inx.

      ls_booking_in  = CORRESPONDING #( ls_booking MAPPING FROM ENTITY ).
      ls_booking_inx = CORRESPONDING #( CORRESPONDING /dmo/s_booking_intx( ls_booking MAPPING FROM ENTITY USING CONTROL ) ).
      ls_booking_inx-action_code = 'C'.
      ls_booking_inx-booking_id  = ls_booking_in-booking_id.
      INSERT ls_booking_in INTO TABLE ct_booking.
      INSERT ls_booking_inx INTO TABLE ct_bookingx.
    ENDLOOP.


  ENDMETHOD.


  METHOD _add_updated_bookings.

    DATA: ls_booking_in  TYPE /dmo/s_booking_in,
          ls_booking_inx TYPE /dmo/s_booking_inx.

    LOOP AT update-booking INTO DATA(ls_booking)
        USING KEY id WHERE TravelID = is_key-travelid.
      "Add updated booking
      CLEAR: ls_booking_in, ls_booking_inx.

      ls_booking_in  = CORRESPONDING #( ls_booking MAPPING FROM ENTITY ).
      ls_booking_inx = CORRESPONDING #( CORRESPONDING /dmo/s_booking_intx( ls_booking MAPPING FROM ENTITY USING CONTROL ) ).
      ls_booking_inx-action_code = 'U'.
      ls_booking_inx-booking_id  = ls_booking_in-booking_id.
      INSERT ls_booking_in INTO TABLE ct_booking.
      INSERT ls_booking_inx INTO TABLE ct_bookingx.
    ENDLOOP.

  ENDMETHOD.


  METHOD _add_deleted_bookings.

    DATA: ls_booking_in  TYPE /dmo/s_booking_in,
          ls_booking_inx TYPE /dmo/s_booking_inx.

    LOOP AT delete-booking INTO DATA(ls_booking)
        USING KEY entity WHERE TravelID = is_key-travelid.
      "add delete booking
      CLEAR: ls_booking_inx, ls_booking_in.
      ls_booking_in-travel_id = is_key-travelid.
      ls_booking_in-booking_id = ls_booking-BookingId.
      INSERT ls_booking_in INTO TABLE ct_booking.
      ls_booking_inx-action_code = 'D'.
      ls_booking_inx-booking_id  = ls_booking-BookingId.
      INSERT ls_booking_inx INTO TABLE ct_bookingx.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
