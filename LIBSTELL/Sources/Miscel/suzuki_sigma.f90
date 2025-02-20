   SUBROUTINE SUZUKI_SIGMA(nion,E_in,ne_in,te_in,ni_in,A_in,Z_in,sigma)
      IMPLICIT NONE
      INTEGER, INTENT(in) :: nion
      DOUBLE PRECISION, INTENT(in)    :: E_in, & !keV/amu
                             ne_in,& !m^-3
                             te_in   !keV
      DOUBLE PRECISION, DIMENSION(nion), INTENT(in)    :: ni_in
      INTEGER, DIMENSION(nion), INTENT(in) :: A_in, &
                                              Z_in
      DOUBLE PRECISION, INTENT(out) :: sigma ! [cm^2]
      INTEGER,DIMENSION(nion) :: ind_H,ind_Z
      INTEGER :: n_H, n_Z, i, j, k, l, m
      REAL :: dense_H, dense_Z, Zeff_sum1, Zeff_sum2, Zeff,&
              logE, logN, U, sigma_H, sigma_Z
      REAL, DIMENSION(3,10) :: A
      REAL, DIMENSION(9,12) :: B
      INTEGER, DIMENSION(9), PARAMETER :: Z_IMP   = (/2, 6, 6, 4, 8, 7, 3, 5, 26/)
      REAL, DIMENSION(9), PARAMETER :: ZEFFMIN_IMP   = (/1.0, 1.0, 5.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 /)
      REAL, DIMENSION(9), PARAMETER :: ZEFFMAX_IMP   = (/2.1, 5.0, 6.0, 4.0, 5.0, 5.0, 3.0, 5.0, 5.0/)
      REAL, PARAMETER :: inv_amu       = 6.02214076208E+26 ! Dalton [amu/kg]

      ! Separate ions into hydrogen species and impurities
      n_H=1; n_Z=1; dense_H=0; dense_Z=0; Zeff_sum1=0; Zeff_sum2=0
      sigma = 0;
      DO i = 1, nion
         IF (Z_in(i) == 1) THEN
            ind_H(n_H) = i
            dense_H = dense_H + ni_in(i)
            n_H = n_H + 1
         ELSE
            ind_Z(n_Z) = i
            dense_Z = dense_Z + ni_in(i)
            n_Z = n_Z + 1
         END IF
         Zeff_sum1 = Zeff_sum1 + ni_in(i)*Z_in(i)*Z_in(i)
         Zeff_sum2 = Zeff_sum2 + ni_in(i)*Z_in(i)
      END DO
      Zeff = Zeff_sum1/Zeff_sum2

      ! Select low- or high-energy coefficient tables
      IF (E_in >= 9 .and. E_in < 100) THEN
         A = RESHAPE((/-52.9, -1.36, 0.0719, 0.0137, 0.454, 0.403, -0.22, 0.0666, -0.0677, -0.00148,&
                       -67.9, -1.22, 0.0814, 0.0139, 0.454, 0.465, -0.273, 0.0751, -0.063, -0.000508,&
                       -74.2, -1.18, 0.0843, 0.0139, 0.453, 0.491, -0.294, 0.0788, -0.0612, -0.000185/),&
                     (/3,10/),ORDER=(/2,1/))
         B = RESHAPE((/-.792000E+00,0.420000E-01,0.530000E-01,-.139000E-01,0.301000E+00,-.264000E-01,-.299000E-01,0.607000E-02,0.272000E-03,0.611000E-02,0.347000E-02,-.919000E-03,&
                       0.161000E+00,0.598000E-01,-.336000E-02,-.426000E-02,-.157000E+00,-.396000E-01,0.460000E-02,0.219000E-02,0.391000E-01,0.711000E-02,-.144000E-02,-.385000E-03,&
                       0.158000E+00,0.554000E-01,-.431000E-02,-.335000E-02,-.155000E+00,-.374000E-01,0.537000E-02,0.174000E-02,0.388000E-01,0.683000E-02,-.160000E-02,-.322000E-03,&
                       0.112000E+00,0.495000E-01,0.116000E-01,-.286000E-02,-.149000E+00,-.331000E-01,-.426000E-02,0.980000E-03,0.447000E-01,0.652000E-02,-.356000E-03,-.203000E-03,&
                       0.111000E+00,0.541000E-01,-.346000E-03,-.368000E-02,-.108000E+00,-.347000E-01,0.193000E-02,0.181000E-02,0.280000E-01,0.604000E-02,-.841000E-03,-.317000E-03,&
                       0.139000E+00,0.606000E-01,-.306000E-02,-.455000E-02,-.133000E+00,-.394000E-01,0.399000E-02,0.236000E-02,0.335000E-01,0.690000E-02,-.124000E-02,-.405000E-03,&
                       0.112000E+00,0.495000E-01,0.116000E-01,-.286000E-02,-.149000E+00,-.331000E-01,-.426000E-02,0.980000E-03,0.447000E-01,0.652000E-02,-.356000E-03,-.203000E-03,&
                       0.122000E+00,0.527000E-01,-.430000E-03,-.318000E-02,-.151000E+00,-.364000E-01,0.343000E-02,0.151000E-02,0.420000E-01,0.692000E-02,-.141000E-02,-.290000E-03,&
                       -.110000E-01,0.202000E-01,0.946000E-03,-.409000E-02,-.666000E-02,-.117000E-01,-.236000E-03,0.202000E-02,0.408000E-02,0.185000E-02,-.648000E-04,-.313000E-03/),&
                     (/9,12/),ORDER=(/2,1/))         
      ELSE IF (E_in<10000) THEN
         A = RESHAPE((/12.7, 1.25, 0.452, 0.0105, 0.547, -0.102, 0.36, -0.0298, -0.0959, 0.00421,&
                      14.1, 1.11, 0.408, 0.0105, 0.547, -0.0403, 0.345, -0.0288, -0.0971, 0.00474,&
                      12.7, 1.26, 0.449, 0.0105, 0.547, -0.00577, 0.336, -0.0282, -0.0974, 0.00487/),&
                     (/3,10/),ORDER=(/2,1/))
         B = RESHAPE((/0.231000,0.343000,-.185000,-.162000E-01,0.105000,-.703000E-01,0.531000E-01,0.342000E-02,-.838000E-02,0.415000E-02,-.335000E-02,-.221000E-03,&
                       -.101000E+01,-.865000E-02,-.124000E+00,-.145000E-01,0.391000E+00,0.161000E-01,0.298000E-01,0.332000E-02,-.248000E-01,-.104000E-02,-.152000E-02,-.189000E-03,&
                       -.100000E+01,-.255000E-01,-.125000E+00,-.142000E-01,0.388000E+00,0.206000E-01,0.297000E-01,0.326000E-02,-.246000E-01,-.131000E-02,-.148000E-02,-.180000E-03,&
                       -.613000E+00,0.552000E-01,-.167000E+00,-.159000E-01,0.304000E+00,0.154000E-02,0.436000E-01,0.378000E-02,-.201000E-01,-.216000E-03,-.251000E-02,-.227000E-03,&
                       -.102000E+01,-.148000E-01,-.674000E-01,-.917000E-02,0.359000E+00,0.143000E-01,0.139000E-01,0.184000E-02,-.209000E-01,-.732000E-03,-.502000E-03,-.949000E-04,&
                       -.102000E+01,-.139000E-01,-.979000E-01,-.117000E-01,0.375000E+00,0.156000E-01,0.224000E-01,0.254000E-02,-.226000E-01,-.889000E-03,-.104000E-02,-.139000E-03,&
                       -.441000E+00,0.129000E+00,-.170000E+00,-.162000E-01,0.277000E+00,-.156000E-01,0.466000E-01,0.379000E-02,-.193000E-01,0.753000E-03,-.286000E-02,-.239000E-03,&
                       -.732000E+00,0.183000E-01,-.155000E+00,-.172000E-01,0.321000E+00,0.946000E-02,0.397000E-01,0.420000E-02,-.204000E-01,-.619000E-03,-.224000E-02,-.254000E-03,&
                       -.820000E+00,-.636000E-02,0.542000E-01,0.395000E-02,0.202000E+00,0.806000E-03,-.200000E-01,-.178000E-02,-.610000E-02,0.651000E-03,0.175000E-02,0.146000E-03/),&
                     (/9,12/),ORDER=(/2,1/))
      ELSE
         RETURN
      ENDIF

      logE = log(E_in)
      logN = log(ne_in*1E-19)
      U    = log(te_in)

      ! Equation 28
      sigma_H = 0
      DO i = 1, n_H-1
         j = ind_H(i)
         k = A_in(j)
         sigma_H = sigma_H + ni_in(j) * (A(k,1)*1.0E-16 / (E_in) &
                                      *(1 + A(k,2)*logE + A(k,3)*logE*logE) &
                                      *(1 + ((1 - exp(-A(k,4)*ne_in*1E-19))**A(k,5)) &
                                          * (A(k,6) + A(k,7)*logE + A(k,8)*logE*logE)) &
                                      *(1 + A(k,9)*U + A(k,10)*U*U))
      END DO
      sigma_H = sigma_H / dense_H

      ! Equation 26 and 27
      sigma_Z = 0
      DO i = 1, n_Z-1
         l = ind_Z(i)
         k = 0
         DO j = 1, 9
            IF (Z_IMP(j) == Z_in(l) .and. Zeff > ZEFFMIN_IMP(j) .and. Zeff < ZEFFMAX_IMP(j)) THEN
               k = j
               CONTINUE
            END IF
         END DO
         IF (k < 0) CONTINUE
         sigma_Z = sigma_Z + ni_in(l) / ne_in * Z_in(l) &
                             *(  B(j,1) + B(j,2)*U + B(j,3)*logN + B(j,4)*logN*U) &
                                                   + B(j,5)*logE + B(j,6)*logE*U  &
                                +B(j,7)*logE*logN + B(j,8) *logE*logN*U &
                                +B(j,9)*logE*logE + B(j,10) *logE*logE*U &
                                +B(j,11)*logE*logE*logN + B(j,12) *logE*logE*logN*U
      END DO

      ! Equation 24
      sigma = sigma_H * (1 + (Zeff - 1) * sigma_Z)

      RETURN
   END SUBROUTINE SUZUKI_SIGMA