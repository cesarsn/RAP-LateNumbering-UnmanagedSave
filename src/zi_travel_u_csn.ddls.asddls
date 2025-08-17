@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Travel data'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZI_Travel_U_CSN 
  as select from /dmo/travel as Travel -- the travel table is the data source for this view

  composition [0..*] of ZI_Booking_U_CSN as _Booking

  association [0..1] to /DMO/I_Agency    as _Agency   on $projection.AgencyID = _Agency.AgencyID
  association [0..1] to /DMO/I_Customer  as _Customer on $projection.CustomerID = _Customer.CustomerID
  association [0..1] to I_Currency       as _Currency on $projection.CurrencyCode = _Currency.Currency
  association [1..1] to /DMO/I_Travel_Status_VH as _TravelStatus on $projection.Status = _TravelStatus.TravelStatus
{
    
  key Travel.travel_id     as TravelID,

      Travel.agency_id     as AgencyID,

      Travel.customer_id   as CustomerID,

      Travel.begin_date    as BeginDate,

      Travel.end_date      as EndDate,
    
      @Semantics.amount.currencyCode: 'CurrencyCode'
      Travel.booking_fee   as BookingFee,

      @Semantics.amount.currencyCode: 'CurrencyCode'
      Travel.total_price   as TotalPrice,

      Travel.currency_code as CurrencyCode,

      Travel.description   as Memo,

      Travel.status        as Status,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true 
      cast( '0' as abp_locinst_lastchange_tstmpl ) as LocalLastChangeDateTime,
      Travel.createdat as CreatedAt,
      Travel.createdby as CreatedBy,
      Travel.lastchangedat as LastChangedAt,
      Travel.lastchangedby as LastChangedBy,

      /* Associations */
      _Booking,
      _Agency,
      _Customer,
      _Currency,
      _TravelStatus
}
