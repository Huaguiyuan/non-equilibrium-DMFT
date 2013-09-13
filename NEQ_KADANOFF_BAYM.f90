!########################################################################
!PURPOSE  : Evolve the Green's functions G^<,R on the real time axis
!given the initial condition at t=t'=0.
!AUTHORS  : Adriano Amaricci
!########################################################################
module NEQ_KADANOFF_BAYM
  !LOCAL:
  USE NEQ_VARS_GLOBAL
  USE ELECTRIC_FIELD
  USE RK24_VIDE
  !
  USE INTEGRATE
  implicit none
  private
  !k-dependent GF
  type(keldysh_contour_gf)                :: Gk
  !local Sigma=Self-energy + Self-bath
  type(keldysh_contour_gf)                :: Skb
  !Chi local
  real(8),allocatable,dimension(:,:,:,:)  :: chik
  !
  public                                  :: neq_get_localgf


contains


  !+-------------------------------------------------------------------+
  !PURPOSE  : Evaluate the k-sum to get the local Green's functions (R,>,<)
  !+-------------------------------------------------------------------+
  subroutine neq_get_localgf()
    call kadanoff_baym_to_localgf()
    call print_out_Gloc()
  end subroutine neq_get_localgf



  !+-------------------------------------------------------------------+
  !PURPOSE  : Build the local Green's functions G^<,R
  ! along the real-time axis, using a discretized verion of the 
  ! Kadanoff-Baym equations. The algorithm is based on collocation method
  ! for the solution of Volterra Integro-Differential Equations.
  ! See Linz "Analytical and Numerical Methods for Volterra Equations" book.
  !+-------------------------------------------------------------------+
  subroutine kadanoff_baym_to_localgf()
    integer                  :: istep,i,j,ik

    call msg("Entering Kadanoff-Baym")

    !Allocate k-dependent GF:
    call allocate_keldysh_contour_gf(Gk,Nstep)
    call allocate_keldysh_contour_gf(Skb,Nstep)
    if(fchi)allocate(chik(2,2,Nstep,Nstep))

    !Set to Zero GF and nk:
    locG   = zero
    nk     = 0.d0

    !this is special for DMFT: k-independent Sigma
    Skb%ret  = S0%ret  + Sigma%ret
    Skb%less = S0%less + Sigma%less

    !=============START K-POINTS LOOP======================
    call start_progress
    do ik=1,Lk
       Gk=zero
       call step_keldysh_contour_gf(ik) !<-- solve the dynamics here:
       if(fchi)then
          call get_chi(ik)
          chi = chi + chik*wt(ik)
       endif
       locG%less = locG%less + Gk%less*wt(ik)
       locG%ret  = locG%ret + Gk%ret*wt(ik)
       call progress(ik,Lk)
    enddo
    call stop_progress
    !=============END K-POINTS LOOP======================

    !Deallocate module arrays:
    call deallocate_keldysh_contour_gf(Gk)
    call deallocate_keldysh_contour_gf(Skb)
    if(fchi)deallocate(chik)
    return 
  end subroutine kadanoff_baym_to_localgf









  !+-------------------------------------------------------------------+
  !PURPOSE  : Solve the Kadanoff-Baym equations as Volterra 
  ! Integro-Differential Equations using Collocation methods
  ! along horizontal lines.
  !+-------------------------------------------------------------------+
  subroutine step_keldysh_contour_gf(ik)
    integer                     :: ik
    integer                     :: i,j
    integer                     :: ytime
    integer                     :: hstride
    integer                     :: Lret
    complex(8)                  :: gless0
    complex(8),dimension(Nstep) :: Hk,QkRet,QkLess

    Qkret=zero

    !SOLVE RETARDED COMPONENT:
    do ytime=1,Nstep
       hstride=ytime-1 ; Lret=Nstep-hstride
       forall(i=1:Lret)Hk(i) = -xi*Hamkt(ik,i,hstride)
       call vide_rk2(dt,Gk%ret(ytime:Nstep,ytime),-xi,Hk,QkRet,-xi*Skb%ret(ytime:Nstep,ytime:Nstep))
    enddo

    !SOLVE LESS COMPONENT:
    forall(i=1:Nstep)Hk(i) = -xi*Hamkt(ik,i,0)
    ytime  = 1
    gless0 =  xi*eq_nk(ik)
    Qkless = -xi*Icollision_less(ytime)
    call vide_rk2(dt,Gk%less(:,ytime),gless0,Hk,Qkless,-xi*Skb%ret)
    do ytime=2,Nstep
       gless0 = -conjg(Gk%less(ytime,1))
       Qkless = -xi*Icollision_less(ytime)
       call vide_rk2(dt,GK%less(:,ytime),gless0,Hk,Qkless,-xi*Skb%ret)
    enddo

    !STORE N(K,T) DISTRIBUTION
    forall(i=1:Nstep)nk(i,ik)=-xi*Gk%less(i,i)
  end subroutine step_keldysh_contour_gf




  !+-------------------------------------------------------------------+
  !PURPOSE  : Evaluate the collision integrals along the whole line t=1:Nt
  ! for t`= ytime
  !+-------------------------------------------------------------------+
  function Icollision_less(ytime) result(Ik)
    integer                     :: ytime
    integer                     :: i
    complex(8),dimension(Nstep) :: Ik
    complex(8),dimension(Nstep) :: gkadv
    ! Ik = \int_0^{t'=ytime} S^<*Gk^A
    gkadv =  conjg(Gk%ret(ytime,:))
    select case(int_method)
    case default
       do i=1,Nstep
          Ik(i) = trapz(dt,Skb%less(i,1:ytime)*gkadv(1:ytime))
       enddo
    case ("simps")
       do i=1,Nstep
          Ik(i) = simps(dt,Skb%less(i,1:ytime)*gkadv(1:ytime))
       enddo
    case ("rect")
       do i=1,Nstep
          Ik(i) = sum(Skb%less(i,1:ytime)*gkadv(1:ytime))*dt
       enddo
    end select
  end function Icollision_less








  !+-------------------------------------------------------------------+
  !PURPOSE  : The code needs a more general implemenation here:
  ! an idea is to use abstract procedure to pass a function as an 
  ! argument of the interface routine, that evaluates for a given 
  ! k-points kx,ky,kz the hamiltonian value H(kx,ky,kz) where the 
  ! k-point may depend on time.
  !+-------------------------------------------------------------------+
  pure function Hamkt(ik,it,stride) result(hk)
    integer,intent(in) :: ik,it,stride
    integer            :: i,j
    real(8)            :: tbar
    type(vect2D)       :: kt,Ak
    real(8)            :: hk
    tbar = time(it+stride)
    i  = ik2ix(ik)
    j  = ik2iy(ik)
    Ak = Afield(tbar,Ek)
    kt = kgrid(i,j) - Ak
    hk = square_lattice_dispersion(kt)
  end function Hamkt






  !+-------------------------------------------------------------------+
  !PURPOSE  : evaluate the susceptibility Chi_k(t,t')
  !+-------------------------------------------------------------------+
  subroutine get_chi(ik)    
    integer      :: ik
    integer      :: i,j,ix,iy
    type(vect2D) :: Ak,kt,vel
    real(8)      :: sx,sy,ex,ey
    !
    chik=zero
    !
    ix=ik2ix(ik)
    iy=ik2iy(ik)
    do i=1,nstep
       Ak = Afield(time(i),Ek)
       kt = kgrid(ix,iy)-Ak
       !vel= square_lattice_velocity(kt)
       sx = 2.d0*sin(kt%x)
       sy = 2.d0*sin(kt%y)
       ex = 2.d0*cos(kt%x)
       ey = 2.d0*cos(kt%y)
       do j=1,nstep
          chik(1,1,i,j)=-2.d0*sx**2*dimag(Gk%ret(i,j)*Gk%less(j,i))
          chik(1,2,i,j)=-2.d0*sx*sy*dimag(Gk%ret(i,j)*Gk%less(j,i))
          chik(2,1,i,j)=-2.d0*sx*sy*dimag(Gk%ret(i,j)*Gk%less(j,i))
          chik(2,2,i,j)=-2.d0*sy**2*dimag(Gk%ret(i,j)*Gk%less(j,i))
       enddo
       chik(1,1,i,i)=chik(1,1,i,i) + 2.d0*ex*xi*Gk%less(i,i)
       chik(2,2,i,i)=chik(2,2,i,i) + 2.d0*ey*xi*Gk%less(i,i)
    enddo
  end subroutine get_chi





  !+-------------------------------------------------------------------+
  !PURPOSE  : print out useful information
  !+-------------------------------------------------------------------+
  subroutine print_out_Gloc()
    integer                         :: i,j,ix,iy,ik
    type(vect2D)                    :: Jk,Ak
    type(vect2D),dimension(1:nstep) :: Jloc                   !local Current 
    real(8),dimension(1:nstep)      :: nt,modJloc             !occupation(time)

    call store_data(trim(data_dir)//"/nk.data",nk)
    if(plot3D)call plot_keldysh_contour_gf(locG,time,trim(plot_dir)//"/Gloc")

    ! forall(i=1:nstep,j=1:nstep)
    !    gf%less%t(i-j) = locG%less(i,j)
    !    gf%ret%t(i-j)  = locG%ret(i,j)
    ! end forall
    ! call fftgf_rt2rw(gf%ret%t,gf%ret%w,nstep) ;  gf%ret%w=gf%ret%w*dt ; call swap_fftrt2rw(gf%ret%w)
    ! call splot("locGless_t.ipt",t,gf%less%t,append=.true.)
    ! call splot("locGret_t.ipt",t,gf%ret%t,append=.true.)
    ! call splot("locGret_realw.ipt",wr,gf%ret%w,append=.true.)
    ! call splot("locDOS.ipt",wr,-aimag(gf%ret%w)/pi,append=.true.)

    forall(i=1:nstep)nt(i)=-xi*locG%less(i,i)

    Jloc=Vzero    
    do ik=1,Lk
       ix=ik2ix(ik);iy=ik2iy(ik)
       do i=1,nstep
          Ak= Afield(time(i),Ek)
          Jk= nk(i,ik)*square_lattice_velocity(kgrid(ix,iy) - Ak)
          Jloc(i) = Jloc(i) +  wt(ik)*Jk
       enddo
    enddo
    call splot("nVStime.ipt",time,2.d0*nt,append=.true.)
    if(Efield/=0.d0)call splot("JlocVStime.ipt",time,Jloc%x,Jloc%y,append=.true.)


    if(fchi)then
       call store_data(trim(data_dir)//"/locChi_11.data",chi(1,1,:,:))
       call store_data(trim(data_dir)//"/locChi_12.data",chi(1,2,:,:))
       call store_data(trim(data_dir)//"/locChi_21.data",chi(2,1,:,:))
       call store_data(trim(data_dir)//"/locChi_22.data",chi(2,2,:,:))
       if(plot3D)then
          call splot3d(trim(plot_dir)//"/locChi_11.ipt",time,time,chi(1,1,:,:))
          call splot3d(trim(plot_dir)//"/locChi_12.ipt",time,time,chi(1,2,:,:))
          call splot3d(trim(plot_dir)//"/locChi_21.ipt",time,time,chi(2,1,:,:))
          call splot3d(trim(plot_dir)//"/locChi_22.ipt",time,time,chi(2,2,:,:))
       endif
    endif

  end subroutine print_out_Gloc






  !******************************************************************
  !******************************************************************
  !******************************************************************






  ! !+-------------------------------------------------------------------+
  ! !PURPOSE  : evaluate the susceptibility (para-magnetic contribution)
  ! !+-------------------------------------------------------------------+
  ! subroutine get_chi_pm(ik)
  !   integer      :: i,j,ik,ix,iy
  !   type(vect2D) :: Ak,kt,vel
  !   real(8)      :: sx,sy
  !   ix=ik2ix(ik)
  !   iy=ik2iy(ik)
  !   do i=0,nstep
  !      Ak = Afield(t(i),Ek)
  !      kt = kgrid(ix,iy)-Ak
  !      !vel= square_lattice_velocity(kt)
  !      sx = 2.d0*sin(kt%x)
  !      sy = 2.d0*sin(kt%y)
  !      do j=0,nstep
  !         chik_pm(1,1,i,j)=-2.d0*sx**2*wt(ik)*dimag(Gk%ret(i,j)*Gk%less(j,i))
  !         chik_pm(1,2,i,j)=-2.d0*sx*sy*wt(ik)*dimag(Gk%ret(i,j)*Gk%less(j,i))
  !         chik_pm(2,1,i,j)=-2.d0*sx*sy*wt(ik)*dimag(Gk%ret(i,j)*Gk%less(j,i))
  !         chik_pm(2,2,i,j)=-2.d0*sy**2*wt(ik)*dimag(Gk%ret(i,j)*Gk%less(j,i))
  !      enddo
  !   enddo
  !   if(plot3d)call splot3d(trim(plot_dir)//"/Chi_PM",t(0:),t(0:),chi_pm(1,1,0:,0:))
  ! end subroutine get_chi_pm


  !   !+-------------------------------------------------------------------+
  !   !PURPOSE  : evaluate the susceptibility (dia-magnetic contribution)
  !   !+-------------------------------------------------------------------+
  !   subroutine get_chi_dia(ik)
  !     integer       :: i,j,ik,ix,iy
  !     type(vect2D)  :: vel,kt,Ak
  !     real(8)       :: eab(2)
  !     ix=ik2ix(ik)
  !     iy=ik2iy(ik)
  !     do i=0,nstep
  !        Ak = Afield(t(i),Ek)
  !        kt = kgrid(ix,iy)-Ak
  !        eab(1)=2.d0*cos(kt%x)
  !        eab(2)=2.d0*cos(kt%y)
  !        chik_dia(1,1,i)=2.d0*wt(ik)*eab(1)*xi*Gk%less(i,i)
  !        chik_dia(2,2,i)=2.d0*wt(ik)*eab(2)*xi*Gk%less(i,i)
  !     enddo
  !  enddo
  !  call splot("ChiDIA_t.ipt",t(0:),chi_dia(1,1,0:))
  ! end subroutine get_chi_dia

end module NEQ_KADANOFF_BAYM
