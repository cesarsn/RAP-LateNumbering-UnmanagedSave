CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Travel RESULT result.
    METHODS GetDefaultsForBookings FOR READ
      IMPORTING keys FOR FUNCTION Travel~GetDefaultsForBookings RESULT result.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD GetDefaultsForBookings.

    "This method will default the id of the new booking by reading all the bookings of
    "the travel and incrementing the highest id by 1.
    data: lt_read_keys type table for READ IMPORT ZI_Travel_U_CSN\\Travel\_Booking,
          ls_read_key like LINE OF lt_read_keys,
          ls_result like LINE OF result.

    loop at keys INTO DATA(ls_key).
      ls_read_key-%tky = ls_key-%tky.   "%TKY includes %is_draft, %pid and TravelId
      insert ls_read_key into table lt_read_keys.
    endloop.

    READ ENTITIES OF ZI_Travel_U_CSN in local mode
        ENTITY Travel by \_Booking
           fields ( TravelID BookingId )
           WITH lt_read_keys
           RESULT DATA(lt_bookings).

    sort lt_bookings BY %is_draft TravelId BookingId DESCENDING.
    delete adjacent duplicates from lt_bookings comparing %is_draft TravelId.

    loop at keys INTO ls_key.
        clear: ls_result.
        try.
            data(ls_booking) = lt_bookings[ key entity %is_draft = ls_key-%is_draft TravelId = ls_key-TravelID ].
        CATCH cx_root.
            clear: ls_booking.
            ls_booking-travelid  = ls_key-TravelID.
            ls_booking-%is_draft = ls_key-%is_draft.
        ENDTRY.
        data(ls_new_booking) = ls_booking.
        ls_new_booking-BookingId = ls_booking-BookingId + 1.
        ls_result-%tky = ls_key-%tky.
        ls_result-%param-TravelID    = ls_new_booking-TravelID.
        ls_result-%param-BookingID   = ls_new_booking-BookingId.
        ls_result-%param-BookingDate = cl_abap_context_info=>get_system_date( ).
        insert ls_result into table result.
    ENDLOOP.



  ENDMETHOD.

ENDCLASS.

CLASS lsc_ZI_TRAVEL_U_CSN DEFINITION INHERITING FROM cl_abap_behavior_saver_failed.
  PROTECTED SECTION.
    types: BEGIN OF ts_key,
             travelid   type /dmo/travel_id,
           END OF ts_key,
           tt_keys type STANDARD TABLE OF ts_key WITH DEFAULT KEY.

    METHODS adjust_numbers REDEFINITION.

    METHODS save_modified REDEFINITION.

    METHODS cleanup_finalize REDEFINITION.
  PRIVATE SECTION.
    TYPES: ts_read_result_travel TYPE STRUCTURE FOR READ RESULT zi_travel_u_csn,
           ts_read_result_booking TYPE TABLE FOR READ RESULT zi_booking_u_csn,
           ts_failed type response for failed late zi_travel_u_csn,
           ts_reported type response for reported late zi_travel_u_csn ,
           ts_mapped type response for mapped late zi_travel_u_csn.

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
     "1.- Create a new travel with bookings
     "2.- Crate a new booking for a existing travel

    data: lt_travel_key type table for READ IMPORT ZI_Travel_U_CSN\\Travel.
    data: lt_booking_key type table for READ IMPORT ZI_Travel_U_CSN\\Booking.

    "Process only if there are changes
    check mapped-travel IS NOT INITIAL OR mapped-booking IS NOT INITIAL.

    "Notice that the read operation is done with %PID, TRAVELID (this last can be ommited as is initial for new travels)
    loop at mapped-travel INTO data(ls_mapped_travel).
        insert value #( %pid = ls_mapped_travel-%pid travelid = ls_mapped_travel-TravelID ) into table lt_travel_key.
    ENDLOOP.
    "Notice that the read operation is done with %PID, TRAVELID, BOOKINGID
    loop at mapped-booking INTO data(ls_mapped_booking).
        insert value #( %pid = ls_mapped_booking-%pid travelid = ls_mapped_booking-%tmp-TravelID bookingid = ls_mapped_booking-%tmp-BookingID ) into table lt_booking_key.
    ENDLOOP.

    READ ENTITIES OF ZI_Travel_U_CSN in local mode
        ENTITY Travel
           all FIELDS WITH CORRESPONDING #( lt_travel_key )
           RESULT DATA(lt_all_travels).

    READ ENTITIES OF ZI_Travel_U_CSN in local mode
        ENTITY Booking
           all FIELDS WITH CORRESPONDING #( lt_booking_key )
           RESULT DATA(lt_all_bookings).


    "Create travel with bookings
    loop at lt_all_travels INTO data(ls_travel).
        data(lt_bookings) = lt_all_bookings.
        delete lt_bookings     where %pidparent <> ls_travel-%pid.
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
    loop at mapped-booking ASSIGNING FIELD-SYMBOL(<fs_booking>)
    where bookingid is INITIAL and
          %tmp-TravelID is NOT INITIAL and
          %tmp-BookingID is not INITIAL.
        <fs_booking>-TravelID  = <fs_booking>-%tmp-TravelID.
        <fs_booking>-Bookingid = <fs_booking>-%tmp-Bookingid.
    ENDLOOP.

  ENDMETHOD.

  METHOD save_modified.
    "Update processing logic to save modified data

  ENDMETHOD.

  METHOD cleanup_finalize.
  ENDMETHOD.


  METHOD _create_travel.

    "Call /DMO/FLIGHT_TRABEL_CREATE function to create travel and bookings
    "Take into account that this API requires two calls: 1 for create and 1 for save (persist data in database)

    data: ls_travel_out TYPE /dmo/travel,
          ls_travel_in TYPE /dmo/s_travel_in,
          ls_booking_in type /dmo/s_booking_in,
          lt_bookings_in type /dmo/t_booking_in,
          lt_messages type /dmo/t_message.

    ls_travel_in = CORRESPONDING #( is_travel MAPPING FROM ENTITY ).
    loop at it_bookings INTO DATA(ls_booking).
      clear: ls_booking_in.
      ls_booking_in = CORRESPONDING #( ls_booking MAPPING FROM ENTITY ).
      insert ls_booking_in into table lt_bookings_in.
    ENDLOOP.

    call FUNCTION '/DMO/FLIGHT_TRAVEL_CREATE'
      EXPORTING
        is_travel             = ls_travel_in
        it_booking            = lt_bookings_in
       IMPORTING
         es_travel            = ls_travel_out
         et_messages          = lt_messages.

    "Map errors as failed
    delete lt_messages where msgty na 'EAX'.

    if lt_messages[] is NOT INITIAL.
        loop at lt_messages into data(ls_message).
            insert value #( %tky = is_travel-%tky
                            %msg = new_message( id       = ls_message-msgid
                                                severity = if_abap_behv_message=>severity-error
                                                number   = ls_message-msgno
                                                v1       = ls_message-msgv1
                                                v2       = ls_message-msgv2
                                                v3       = ls_message-msgv3
                                                v4       = ls_message-msgv4 )
                            ) into table reported-travel.
        ENDLOOP.
        insert value #( %tky = is_travel-%tky ) into TABLE failed-travel.
        return.
    endif.

    "Save to database
    call FUNCTION '/DMO/FLIGHT_TRAVEL_SAVE'.

    "Map ids in mapping table
    "Travekl
    READ TABLE mapped-travel ASSIGNING FIELD-SYMBOL(<fs_mapped_travel>)
      WITH KEY id components %pid = is_travel-%pid.
    <fs_mapped_travel>-TravelID = ls_travel_out-travel_id.

    loop at it_bookings ASSIGNING FIELD-SYMBOL(<fs_booking>)
      where %pidparent = is_travel-%pid.
      "Map booking id
      READ TABLE mapped-booking ASSIGNING FIELD-SYMBOL(<fs_mapped_booking>)
        WITH KEY id components %pid = <fs_booking>-%pid.
      <fs_mapped_booking>-BookingId = <fs_booking>-BookingId.
      <fs_mapped_booking>-TravelID  = ls_travel_out-travel_id.


    endloop.

  ENDMETHOD.

ENDCLASS.
