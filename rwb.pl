#!/usr/bin/perl -w

#
#
# rwb.pl (Red, White, and Blue)
#
#
# Example code for EECS 339, Northwestern University
# 
# Peter Dinda
#

# The overall theory of operation of this script is as follows
#
# 1. The inputs are form parameters, if any, and a session cookie, if any. 
# 2. The session cookie contains the login credentials (User/Password).
# 3. The parameters depend on the form, but all forms have the following three
#    special parameters:
#
#         act      =  form  <the form in question> (form=base if it doesn't exist)
#         run      =  0 Or 1 <whether to run the form or not> (=0 if it doesn't exist)
#         debug    =  0 Or 1 <whether to provide debugging output or not> 
#
# 4. The script then generates relevant html based on act, run, and other 
#    parameters that are form-dependent
# 5. The script also sends back a new session cookie (allowing for logout functionality)
# 6. The script also sends back a debug cookie (allowing debug behavior to propagate
#    to child fetches)
#


#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();

#
# The combination of -w and use strict enforces various 
# rules that make the script more resilient and easier to run
# as a CGI script.
#
use strict;

# The CGI web generation stuff
# This helps make it easy to generate active HTML content
# from Perl
#
# We'll use the "standard" procedural interface to CGI
# instead of the OO default interface
use CGI qw(:standard);


# The interface to the database.  The interface is essentially
# the same no matter what the backend database is.  
#
# DBI is the standard database interface for Perl. Other
# examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
#
#
# This will also load DBD::Oracle which is the driver for
# Oracle.
use DBI;

#
#
# A module that makes it easy to parse relatively freeform
# date strings into the unix epoch time (seconds since 1970)
#
use Time::ParseDate;



#
# You need to override these for access to your database
#
my $dbuser="jjp1083";
my $dbpasswd="zc8ja9WOp";


#
# The session cookie will contain the user's name and password so that 
# he doesn't have to type it again and again. 
#
# "RWBSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
my $cookiename="RWBSession";
#
# And another cookie to preserve the debug state
#
my $debugcookiename="RWBDebug";

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);

#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie=0;
my $user = undef;
my $password = undef;
my $logincomplain=0;
my $input = 1;
#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
my $action;
my $run;


if (defined(param("act"))) { 
  $action=param("act");
  if (defined(param("run"))) { 
    $run = param("run") == 1;
  } else {
    $run = 0;
  }
} else {
  $action="base";
  $run = 1;
}

my $dstr;

if (defined(param("debug"))) { 
  # parameter has priority over cookie
  if (param("debug") == 0) { 
    $debug = 0;
  } else {
    $debug = 1;
  }
} else {
  if (defined($inputdebugcookiecontent)) { 
    $debug = $inputdebugcookiecontent;
  } else {
    # debug default from script
  }
}

$outputdebugcookiecontent=$debug;

#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if (defined($inputcookiecontent)) { 
  # Has cookie, let's decode it
  ($user,$password) = split(/\//,$inputcookiecontent);
  $outputcookiecontent = $inputcookiecontent;
} else {
  # No cookie, treat as anonymous user
  ($user,$password) = ("anon","anonanon");
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ($action eq "login") { 
  if ($run) { 
    #
    # Login attempt
    #
    # Ignore any input cookie.  Just validate user and
    # generate the right output cookie, if any.
    #
    ($user,$password) = (param('user'),param('password'));
    if (ValidUser($user,$password)) { 
      # if the user's info is OK, then give him a cookie
      # that contains his username and password 
      # the cookie will expire in one hour, forcing him to log in again
      # after one hour of inactivity.
      # Also, land him in the base query screen
      $outputcookiecontent=join("/",$user,$password);
      $action = "base";
      $run = 1;
    } else {
      # uh oh.  Bogus login attempt.  Make him try again.
      # don't give him a cookie
      $logincomplain=1;
      $action="login";
      $run = 0;
    }
  } else {
    #
    # Just a login screen request, but we should toss out any cookie
    # we were given
    #
    undef $inputcookiecontent;
    ($user,$password)=("anon","anonanon");
  }
} 


#
# If we are being asked to log out, then if 
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
  $deletecookie=1;
  $action = "base";
  $user = "anon";
  $password = "anonanon";
  $run = 1;
}


my @outputcookies;

#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right 
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if (defined($outputcookiecontent)) { 
  my $cookie=cookie(-name=>$cookiename,
		    -value=>$outputcookiecontent,
		    -expires=>($deletecookie ? '-1h' : '+1h'));
  push @outputcookies, $cookie;
} 
#
# We also send back a debug cookie
#
#
if (defined($outputdebugcookiecontent)) { 
  my $cookie=cookie(-name=>$debugcookiename,
		    -value=>$outputdebugcookiecontent);
  push @outputcookies, $cookie;
}

#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#
print header(-expires=>'now', -cookie=>\@outputcookies);

#
# Now we finally begin generating back HTML
#
#
#print start_html('Red, White, and Blue');
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Red, White, and Blue</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

#
# Force device width, for mobile phones, etc
#
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
#
print "<style type=\"text/css\">\n\@import \"rwb.css\";\n</style>\n";
  

print "<center>" if !$debug;


#
#
# The remainder here is essentially a giant switch statement based
# on $action. 
#
#
#


# LOGIN
#
# Login is a special case since we handled running the filled out form up above
# in the cookie-handling code.  So, here we only show the form if needed
# 
#
if ($action eq "login") { 
  if ($logincomplain) { 
    print "Login failed.  Try again.<p>"
  } 
  if ($logincomplain or !$run) { 
    print start_form(-name=>'Login'),
      h2('Login to Red, White, and Blue'),
	"Name:",textfield(-name=>'user'),	p,
	  "Password:",password_field(-name=>'password'),p,
	    hidden(-name=>'act',default=>['login']),
	      hidden(-name=>'run',default=>['1']),
		submit,
		  end_form;
  }
}



#
# BASE
#
# The base action presents the overall page to the browser
# This is the "document" that the JavaScript manipulates
#
#
if ($action eq "base") { 
  #
  # Google maps API, needed to draw the map
  #
  print "<script src=\"http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js\" type=\"text/javascript\"></script>";
  print "<script src=\"http://maps.google.com/maps/api/js?sensor=false\" type=\"text/javascript\"></script>";
  
  #
  # The Javascript portion of our app
  #
  print "<script type=\"text/javascript\" src=\"rwb.js\"> </script>";



  #
  #
  # And something to color (Red, White, or Blue)
  #
  print "<div id=\"color\" style=\"width:100\%; height:10\%\"></div>";

  #
  #
  # And a map which will be populated later
  #
  print "<div id=\"map\" style=\"width:100\%; height:80\%\"></div>";
  
  
  #
  # And a div to populate with info about nearby stuff
  #
  #
  if ($debug) {
    # visible if we are debugging
    print "<div id=\"data\" style=\:width:100\%; height:10\%\"></div>";
  } else {
    # invisible otherwise
    print "<div id=\"data\" style=\"display: none;\"></div>";
  }


# height=1024 width=1024 id=\"info\" name=\"info\" onload=\"UpdateMap()\"></iframe>";
  

  #
  # User mods
  #
  #

 if ($user eq "anon") {
    print "<p>You are anonymous, but you can also <a href=\"rwb.pl?act=login\">login</a></p>";
  } else {
    print "<p>You are logged in as $user and can do the following:</p>";
  print"<br><p>Please select data to show on map</p>";
 
  print "<input type='checkbox' name='committee' value='committees'> Committee"; 
  print "<input type='checkbox' name='candidate' value='candidates'> Candidate";
  print "<input type='checkbox' name='individual' value='individuals'> Individual"; 

use strict;
print "<br><p>please select cycle(the start year, if you chose 2010, the cycle is 2010 to 2011)</p>";

print qq{<select name="year">\n};
my @years =  GetCycle();
print @years;
foreach my $year (@years) {
print $year;
    print qq{<option value="$year">$year</option>\n};
}
print qq{</select>};  
  if (UserCan($user,"give-opinion-data")) {
      print "<p><a href=\"rwb.pl?act=give-opinion-data\">Give Opinion Of Current Location</a></p>";
    }
    if (UserCan($user,"give-cs-ind-data")) {
      print "<p><a href=\"rwb.pl?act=give-cs-ind-data\">Geolocate Individual Contributors</a></p>";
    }
    if (UserCan($user,"manage-users") || UserCan($user,"invite-users")) {
      print "<p><a href=\"rwb.pl?act=invite-user\">Invite User</a></p>";
    }
    if (UserCan($user,"manage-users") || UserCan($user,"add-users")) { 
      print "<p><a href=\"rwb.pl?act=add-user\">Add User</a></p>";
    } 
    if (UserCan($user,"manage-users")) { 
      print "<p><a href=\"rwb.pl?acti=delete-user\">Delete User</a></p>";
      print "<p><a href=\"rwb.pl?act=add-perm-user\">Add User Permission</a></p>";
      print "<p><a href=\"rwb.pl?act=revoke-perm-user\">Revoke User Permission</a></p>";
    }
    print "<p><a href=\"rwb.pl?act=logout&run=1\">Logout</a></p>";
  }


}

   








#
#
# NEAR
#
#
# Nearby committees, candidates, individuals, and opinions
#
#
# Note that the individual data should integrate the FEC data and the more
# precise crowd-sourced location data.   The opinion data is completely crowd-sourced
#
# This form intentionally avoids decoration since the expectation is that
# the client-side javascript will invoke it to get raw data for overlaying on the map
#
#
if ($action eq "near") {

  my $latne = param("latne");
  my $longne = param("longne");
  my $latsw = param("latsw");
  my $longsw = param("longsw");
  my $whatparam = param("what");
  my $format = param("format");
  my $cycle = param("cycle");
  my %what;
  $format = "table" if !defined($format);
  $cycle = "1112" if !defined($cycle);
  #$cycle = $period;
if (!defined($whatparam) || $whatparam eq "all") { 
#print "<h2>//////$c1</h2>";  

 %what = ( committees =>1, 
	      candidates =>1,
	      individuals =>1,
	      opinions => 1);
 } else {
    map {$what{$_}=1} split(/,/,$whatparam);
  }
	       

 if ($what{committees}) { 
    my ($str,$error) = Committees($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby committees</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{candidates}) {
    my ($str,$error) = Candidates($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby candidates</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{individuals}) {
    my ($str,$error) = Individuals($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby individuals</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{opinions}) {
    my ($str,$error) = Opinions($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby opinions</h2>$str";
      } else {
	print $str;
      }
    }
  }
}

# if ($action eq "invite-user") { 
#   print h2("Invite User Functionality Is Unimplemented");
# }

if ($action eq "invite-user") {
  print h2("Invite User Functionality");
  if(!UserCan($user, ,"invite-users")){
    print h3("You do not have the permission to invite users.");
  }
  else{
    if (!$run) { 
      print start_form(-name=>'InviteUser'),
      h2('Invite User'),
      "Enter user email: ", textfield(-name=>'email'),
      p,
      hidden(-name=>'run',-default=>['1']),
      hidden(-name=>'act',-default=>['invite-user']),
      submit,
      end_form,
      hr;
    }
    else {
      my $email=param('email');
      my $code=1000000 + int(rand(9999999 - 1000000));
      open(MAIL,"| mail -s 'Invitation to RWB!' $email") or die "Can't run mail\n";
      print MAIL "Click here for your one-time invitation to RWB: http://murphy.wot.eecs.northwestern.edu/~xwi5328/rwb/rwb.pl?act=accept-invitatioin&email=$email&code=$code&referer=$user"; 
      close(MAIL);
      AddInviteCode($email, $code);
      print "Sent invitation to $email from $user\n";
      }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

if($action eq "accept-invitatioin"){
  if (!$run){
    print 
    header,
    start_html('Create Account'),
    h2('Create Account'),
    start_form,
    "Enter your name ",textfield('name'),p,
    "Enter your email ",textfield('email'),p,
    "Enter your password", textfield('password'),p,
    hidden("code: ", textfield(-name=>'code')),
    hidden("referer", textfield(-name=>'referer')), p,
    hidden(-name=>'run',-default=>['1']),
    hidden(-name=>'act',-default=>['accept-invitatioin']),
    submit,
    end_form,
    end_html;
  } else {
    print 
    header,
    my $name = param('name');
    my $email = param('email');
    my $referer = param('referer');
    my $password = param('password');
    my $code = param('code');
    my $lcheckCode = CheckCode($code);
    my $error = UserAdd($name,$password,$email, $referer);  
    if($error) {
      print "Can' not register because: $error";
    } else{
      RmLink($code);
      print "You are registered as $name ($email) ";
    }
  }
}


# if ($action eq "give-opinion-data") { 
#   print h2("Giving Location Opinion Data Is Unimplemented");
# }

if ($action eq "give-opinion-data") {
  print h2("Invite User Functionality");
  if(!UserCan($user, ,"give-opinion-data")){
    print h3("You do not have the permission to give opinion.");
  }
  else{
    # a form that enable user to give opinion to current location 
    if(!$run) {
      print
      header,
      start_html('GiveOpinion'),
      h2('Give opinion'),
      start_form,
      checkbox_group(-name=>'choose_opinion',
        -values=>['red','write','blue']),
      submit,
      end_form,
       "<script type=\"text/javascript\" src=\"getlocation.js\"> </script>";
      end_html;
    } else {
      my @checked_boxes = param('choose_opinion');
      print h3("You picked $checked_boxes[0]");  # want to give a notice that the user have choosen some opiniom..
      my $username = $user;
      my $opinion = $checked_boxes[0];
      my $lat = param('lati');
      my $long = param('longi'); ## 'long' or 'longitude' ???
      my $error = AddOpinion2DB($username, $opinion, $lat, $long); # wondering where do the data ( parameters) come from?????
      if ($error) {
        print "Can't add opinion because: $error";
      } else {
        print "Opinion added.\n";
      }
    }
  }
    print "<p><a href=\"rwb-mobile.pl?act=base&run=1\">Return</a></p>"; 
}


if ($action eq "give-cs-ind-data") { 
  print h2("Giving Crowd-sourced Individual Geolocations Is Unimplemented");
}


#
#
# aggregate function
#
if ( $action eq "sum" ) {
    my $latne     = param("latne");
    my $longne    = param("longne");
    my $latsw     = param("latsw");
    my $longsw    = param("longsw");
    my $whatparam = param("what");
    my $format    = param("format");
    my $cycle     = param("cycle");
    my %what;

    $format = "table" if !defined($format);
    $cycle  = "1112"  if !defined($cycle);

    if ( !defined($whatparam) || $whatparam eq "all" ) {
        %what = (
            committees  => 1,
            candidates  => 1,
            individuals => 1,
            opinions    => 1
        );
    }
    else {
        map { $what{$_} = 1 } split( /\s*,\s*/, $whatparam );
    }

    if ( $what{committees} ) {
        my ( $cm2cmt, $c2cm_color, $error1 )
            = Aggr_Comm2Comm( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ($error1) {
            print "Error in Comm2Comm summary data";
        }
        else {
            print "<h3>Committee to Committee Summary</h3>";
            print $cm2cmt;
        }

        my ( $cm2cnd, $c2cd_color, $error2 )
            = Aggr_Comm2Cand( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ($error2) {
            print "Error in Comm2Cand summary data";
        }
        else {
            print "<h3>Committee to Candidate Summary</h3>";
            print $cm2cnd;
        }
    }

    if ( $what{candidates} ) {
        my ( $str, $error )
            = Candidates( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error ) {
            if ( $format eq "table" ) {
                print "<h2>Nearby candidates</h2>$str";
            }
            else {
                print $str;
            }
        }
    }

    if ( $what{individuals} ) {
        my ( $ind, $ind_color, $error3 )
            = Aggr_Individuals( $latne, $longne, $latsw, $longsw,
            $cycle, $format );
        if ($error3) {
            print "Error in Individual summary data";
        }
        else {
            print "<h3>Individual Summary</h3>";
            print $ind;
        }
    }

    if ( $what{opinions} ) {
        my ( $opn, $op_color, $error4 )
            = Aggr_Opinions( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ($error4) {
            print "Error in Opinion summary data";
        }
        else {
            print "<h3>Opinion Summary</h3>";
            print $opn;
        }
    }
}



#
# ADD-USER
#
# User Add functionaltiy 
#
#
#
#
if ($action eq "add-user") { 
  if (!UserCan($user,"add-users") && !UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to add users.');
  } else {
    if (!$run) { 
      print start_form(-name=>'AddUser'),
	h2('Add User'),
	  "Name: ", textfield(-name=>'name'),
	    p,
	      "Email: ", textfield(-name=>'email'),
		p,
		  "Password: ", textfield(-name=>'password'),
		    p,
		      hidden(-name=>'run',-default=>['1']),
			hidden(-name=>'act',-default=>['add-user']),
			  submit,
			    end_form,
			      hr;
    } else {
      my $name=param('name');
      my $email=param('email');
      my $password=param('password');
      my $error;
      $error=UserAdd($name,$password,$email,$user);
      if ($error) { 
	print "Can't add user because: $error";
      } else {
	print "Added user $name $email as referred by $user\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# DELETE-USER
#
# User Delete functionaltiy 
#
#
#
#
if ($action eq "delete-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to delete users.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'DeleteUser'),
	h2('Delete User'),
	  "Name: ", textfield(-name=>'name'),
	    p,
	      hidden(-name=>'run',-default=>['1']),
		hidden(-name=>'act',-default=>['delete-user']),
		  submit,
		    end_form,
		      hr;
    } else {
      my $name=param('name');
      my $error;
      $error=UserDel($name);
      if ($error) { 
	print "Can't delete user because: $error";
      } else {
	print "Deleted user $name\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# ADD-PERM-USER
#
# User Add Permission functionaltiy 
#
#
#
#
if ($action eq "add-perm-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to manage user permissions.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'AddUserPerm'),
	h2('Add User Permission'),
	  "Name: ", textfield(-name=>'name'),
	    "Permission: ", textfield(-name=>'permission'),
	      p,
		hidden(-name=>'run',-default=>['1']),
		  hidden(-name=>'act',-default=>['add-perm-user']),
		  submit,
		    end_form,
		      hr;
      my ($table,$error);
      ($table,$error)=PermTable();
      if (!$error) { 
	print "<h2>Available Permissions</h2>$table";
      }
    } else {
      my $name=param('name');
      my $perm=param('permission');
      my $error=GiveUserPerm($name,$perm);
      if ($error) { 
	print "Can't add permission to user because: $error";
      } else {
	print "Gave user $name permission $perm\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# REVOKE-PERM-USER
#
# User Permission Revocation functionaltiy 
#
#
#
#
if ($action eq "revoke-perm-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to manage user permissions.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'RevokeUserPerm'),
	h2('Revoke User Permission'),
	  "Name: ", textfield(-name=>'name'),
	    "Permission: ", textfield(-name=>'permission'),
	      p,
		hidden(-name=>'run',-default=>['1']),
		  hidden(-name=>'act',-default=>['revoke-perm-user']),
		  submit,
		    end_form,
		      hr;
      my ($table,$error);
      ($table,$error)=PermTable();
      if (!$error) { 
	print "<h2>Available Permissions</h2>$table";
      }
    } else {
      my $name=param('name');
      my $perm=param('permission');
      my $error=RevokeUserPerm($name,$perm);
      if ($error) { 
	print "Can't revoke permission from user because: $error";
      } else {
	print "Revoked user $name permission $perm\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}



#
#
#
#
# Debugging output is the last thing we show, if it is set
#
#
#
#

print "</center>" if !$debug;

#
# Generate debugging output if anything is enabled.
#
#
if ($debug) {
  print hr, p, hr,p, h2('Debugging Output');
  print h3('Parameters');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(param($_)) } param();
  print "</menu>";
  print h3('Cookies');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(cookie($_))} cookie();
  print "</menu>";
  my $max= $#sqlinput>$#sqloutput ? $#sqlinput : $#sqloutput;
  print h3('SQL');
  print "<menu>";
  for (my $i=0;$i<=$max;$i++) { 
    print "<li><b>Input:</b> ".escapeHTML($sqlinput[$i]);
    print "<li><b>Output:</b> $sqloutput[$i]";
  }
  print "</menu>";
}

print end_html;

#
# The main line is finished at this point. 
# The remainder includes utilty and other functions
#


#
# Generate a table of nearby committees
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Committees {
  my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
  my @rows;
  eval { 
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",undef,$cycle,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("committee_data","2D",
			["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],
			@rows),$@);
    } else {
      return (MakeRaw("committee_data","2D",@rows),$@);
    }
  }
}


#
# Generate an aggregated table of nearby committee money, grouped by party
# ($table|$raw,$error) = Aggr_Comm2Cand(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Aggr_Comm2Cand {

    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my ( @rows, @dems, @reps );
    my ( $dem, $rep, $color ) = ( 0, 0, "white" );
    my $try = 0;

    while ( ( $dem == 0 || $rep == 0 ) && $try <= 5 ) {
        eval {
            @dems = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation, cycle from cs339.committee_master where cmte_pty_affiliation in ('DEM','Dem','dem')) natural join cs339.cmte_id_to_geo natural join (select cmte_id, transaction_amnt from cs339.comm_to_cand) where  latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total DEM amts
        $dem = $dems[0][0];
        if ( defined $dem ) {
            $dem = $dem;
        }
        else {
            $dem = 0;
        }

        eval {
            @reps = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation, cycle from cs339.committee_master where cmte_pty_affiliation in ('REP','Rep','rep','GOP')) natural join cs339.cmte_id_to_geo natural join (select cmte_id, transaction_amnt from cs339.comm_to_cand) where  latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total REP amts
        $rep = $reps[0][0];
        if ( defined $rep ) {
            $rep = $rep;
        }
        else {
            $rep = 0;
        }

        $latsw -= ( $latne - $latsw ) / 2;
        $latne += ( $latne - $latsw ) / 2;
        $longsw -= ( $longne - $longsw ) / 2;
        $longne += ( $longne - $longsw ) / 2;
        $try++;

    }

    if ( $rep > $dem ) {
        $color = "red";
    }
    elsif ( $dem > $rep ) {
        $color = "blue";
    }
    else {
        $color = "white";
    }

    @rows = ( [ "REP", $rep ], [ "DEM", $dem ] );

    if ($@) {
        return ( undef, $color, $@ );
    }
    else {
        return (
            MakeTableColor(
                "comm2cand_summary", "2D",
                [ "Party", "Amount" ], $color,
                @rows
            ),
            $color, $@
        );
    }
}

#
# Generate an aggregated table of nearby committee money, grouped by party
# ($table|$raw,$error) = Aggr_Comm2Comm(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Aggr_Comm2Comm {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my ( @rows, @dems, @reps );
    my ( $dem, $rep, $color ) = ( 0, 0, "white" );
    my $try = 0;

    while ( ( $dem == 0 || $rep == 0 ) && $try <= 5 ) {

        eval {
            @dems = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation, cycle from cs339.committee_master where cmte_pty_affiliation in ('DEM','Dem','dem')) natural join cs339.cmte_id_to_geo natural join (select cmte_id, transaction_amnt from cs339.comm_to_comm) where latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total DEM amts
        $dem = $dems[0][0];
        if ( defined $dem ) {
            $dem = $dem;
        }
        else {
            $dem = 0;
        }

        eval {
            @reps = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation, cycle from cs339.committee_master where cmte_pty_affiliation in ('REP','Rep','rep')) natural join cs339.cmte_id_to_geo natural join (select cmte_id, transaction_amnt from cs339.comm_to_comm) where  latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total REP amts
        $rep = $reps[0][0];
        if ( defined $rep ) {
            $rep = $rep;
        }
        else {
            $rep = 0;
        }

        $latsw -= ( $latne - $latsw ) / 2;
        $latne += ( $latne - $latsw ) / 2;
        $longsw -= ( $longne - $longsw ) / 2;
        $longne += ( $longne - $longsw ) / 2;
        $try++;

    }  

    if ( $rep > $dem ) {
        $color = "red";
    }
    elsif ( $dem > $rep ) {
        $color = "blue";
    }
    else {
        $color = "white";
    }

    @rows = ( [ "REP", $rep ], [ "DEM", $dem ] );

    if ($@) {
        return ( undef, $@ );
    }
    else {
        return (
            MakeTableColor(
                "comm2comm_summary", "2D",
                [ "Party", "Amount" ], $color,
                @rows
            ),
            $color, $@
        );
    }
}


#
# Generate a table of nearby candidates
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Candidates {
  my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
  my @rows;
  eval { 
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cand_name, cand_pty_affiliation, cand_st1, cand_st2, cand_city, cand_st, cand_zip from cs339.candidate_master natural join cs339.cand_id_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",undef,$cycle,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") {
      return (MakeTable("candidate_data", "2D",
			["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],
			@rows),$@);
    } else {
      return (MakeRaw("candidate_data","2D",@rows),$@);
    }
  }
}


#
# Generate a table of nearby individuals
#
# Note that the handout version does not integrate the crowd-sourced data
#
# ($table|$raw,$error) = Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Individuals {
  my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
  my @rows;
  eval { 
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, name, city, state, zip_code, employer, transaction_amnt from cs339.individual natural join cs339.ind_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",undef,$cycle,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("individual_data", "2D",
			["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
			@rows),$@);
    } else {
      return (MakeRaw("individual_data","2D",@rows),$@);
    }
  }
}


#
# Generate an aggregated table of nearby individual money, grouped by party
# ($table|$raw,$error) = Aggr_Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Aggr_Individuals {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my ( @rows, @dems, @reps );
    my ( $dem, $rep, $color ) = ( 0, 0, "white" );
    my $try = 0;


    while ( ( $dem == 0 || $rep == 0 ) && $try <= 2 ) {

        eval {
            @dems = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation from cs339.committee_master where cmte_pty_affiliation in ('DEM','Dem','dem')) natural join cs339.ind_to_geo natural join (select cmte_id, transaction_amnt, cycle, sub_id from cs339.individual) where latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total DEM amts
        $dem = $dems[0][0];
        if ( defined $dem ) {
            $dem = $dem;
        }
        else {
            $dem = 0;
        }

        eval {
            @reps = ExecSQL(
                $dbuser,
                $dbpasswd,

                "select sum(transaction_amnt) from (select cmte_ID, cmte_pty_affiliation from cs339.committee_master where cmte_pty_affiliation in ('REP','rep','Rep','GOP')) natural join cs339.ind_to_geo natural join (select cmte_id, transaction_amnt, cycle, sub_id from cs339.individual) where latitude>? and latitude<? and longitude>? and longitude<? and cycle = ?", 
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne,
                $cycle
            );
        };

        # find the total REP amts
        $rep = $reps[0][0];
        if ( defined $rep ) {
            $rep = $rep;
        }
        else {
            $rep = 0;
        }

        $latsw -= ( $latne - $latsw ) / 2;
        $latne += ( $latne - $latsw ) / 2;
        $longsw -= ( $longne - $longsw ) / 2;
        $longne += ( $longne - $longsw ) / 2;
        $try++;
    }

    if ( $rep > $dem ) {
        $color = "red";
    }
    elsif ( $dem > $rep ) {
        $color = "blue";
    }
    else {
        $color = "white";
    }

    @rows = ( [ "REP", $rep ], [ "DEM", $dem ] );

    if ($@) {
        return ( undef, $color, $@ );
    }
    else {
        return (
            MakeTableColor(
                "individual_summary", "2D",
                [ "Party", "Amount" ], $color,
                @rows
            ),
            $color, $@
        );
    }
}


#
# Generate a table of nearby opinions
#
# ($table|$raw,$error) = Opinions(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Opinions {
  my ($latne, $longne, $latsw, $longsw, $cycle,$format) = @_;
  my @rows;
  eval { 
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, color from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("opinion_data","2D",
			["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
			@rows),$@);
    } else {
      return (MakeRaw("opinion_data","2D",@rows),$@);
    }
  }
}



#
# Generate an aggregated table of nearby opinions, grouped by party
# ($table|$raw,$error) = Aggr_Opinions(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Aggr_Opinions {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my ( @rows, @avgs, @stds );
    my ( $avg, $std, $color ) = ( 0, 0, "white" );
    my $try = 0;

    while ( $avg == 0 && $try <= 3 ) {

        eval {
            @avgs = ExecSQL(
                $dbuser,
                $dbpasswd,
                "select avg(color) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
        };

        # find the total AVG amts
        $avg = $avgs[0][0];
        if ( defined $avg ) {
            $avg = $avg;
        }
        else {
            $avg = 0;
        }

        eval {
            @stds = ExecSQL(
                $dbuser,
                $dbpasswd,
                "select stddev(color) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
        };

        # find the total AVG amts
        $std = $stds[0][0];
        if ( defined $std ) {
            $std = $std;
        }
        else {
            $std = 0;
        }

        $latsw -= ( $latne - $latsw ) / 2;
        $latne += ( $latne - $latsw ) / 2;
        $longsw -= ( $longne - $longsw ) / 2;
        $longne += ( $longne - $longsw ) / 2;
        $try++;
    }

    if ( $avg > 0 ) {

        $color = "blue";
    }
    elsif ( $avg < 0 ) {
        $color = "red";

    }
    else {
        $color = "white";
    }

    @rows = ( [ $avg, $std ] );

    if ($@) {
        return ( undef, $color, $@ );
    }
    else {
        return (
            MakeTableColor(
                "opinion_summary", "2D",
                [ "Average", "Std Dev" ], $color,
                @rows
            ),
            $color, $@
        );
    }
}

sub GetCycle {

	my @rows;
my $querystring= "select distinct cycle from cs339.individual order by cycle";
my $dbh = DBI->connect("DBI:Oracle:",$dbuser, $dbpasswd);
 my $sth = $dbh->prepare($querystring);
     $sth->execute();

 my $data1;
  while ($data1=$sth->fetchrow_array()) {
    push @rows, $data1;}
$sth->finish();

  $dbh->disconnect();
	return @rows;
}
#
# Generate a table of available permissions
# ($table,$error) = PermTable()
# $error false on success, error string on failure
#
sub PermTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select action from rwb_actions"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("perm_table",
		      "2D",
		     ["Perm"],
		     @rows),$@);
  }
}

#
# Generate a table of users
# ($table,$error) = UserTable()
# $error false on success, error string on failure
#
sub UserTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select name, email from rwb_users order by name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("user_table",
		      "2D",
		     ["Name", "Email"],
		     @rows),$@);
  }
}

#
# Generate a table of users and their permissions
# ($table,$error) = UserPermTable()
# $error false on success, error string on failure
#
sub UserPermTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select rwb_users.name, rwb_permissions.action from rwb_users, rwb_permissions where rwb_users.name=rwb_permissions.name order by rwb_users.name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("userperm_table",
		      "2D",
		     ["Name", "Permission"],
		     @rows),$@);
  }
}

#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
# 
# UserAdd($name,$password,$email)
#
sub UserAdd { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_users (name,password,email,referer) values (?,?,?,?)",undef,@_);};
  return $@;
}

#
# Delete a user
# returns false on success, $error string on failure
# 
sub UserDel { 
  eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_users where name=?", undef, @_);};
  return $@;
}


#
# Give a user a permission
#
# returns false on success, error string on failure.
# 
# GiveUserPerm($name,$perm)
#



sub GiveUserPerm { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_permissions (name,action) values (?,?)",undef,@_);};
  return $@;
}

#
# Revoke a user's permission
#
# returns false on success, error string on failure.
# 
# RevokeUserPerm($name,$perm)
#
sub RevokeUserPerm { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "delete from rwb_permissions where name=? and action=?",undef,@_);};
  return $@;
}

#
#
# Check to see if user and password combination exist
#
# $ok = ValidUser($user,$password)
#
#
sub ValidUser {
  my ($user,$password)=@_;
  my @col;
  eval {@col=ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_users where name=? and password=?","COL",$user,$password);};
  if ($@) { 
    return 0;
  } else {
    return $col[0]>0;
  }
}


#
#
# Check to see if user can do some action
#
# $ok = UserCan($user,$action)
#
sub UserCan {
  my ($user,$action)=@_;
  my @col;
  eval {@col= ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_permissions where name=? and action=?","COL",$user,$action);};
  if ($@) { 
    return 0;
  } else {
    return $col[0]>0;
  }
}





#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
sub MakeTable {
  my ($id,$type,$headerlistref,@list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  if ((defined $headerlistref) || ($#list>=0)) {
    # if there is, begin a table
    #
    $out="<table id=\"$id\" border>";
    #
    # if there is a header list, then output it in bold
    #
    if (defined $headerlistref) { 
      $out.="<tr>".join("",(map {"<td><b>$_</b></td>"} @{$headerlistref}))."</tr>";
    }
    #
    # If it's a single row, just output it in an obvious way
    #
    if ($type eq "ROW") { 
      #
      # map {code} @list means "apply this code to every member of the list
      # and return the modified list.  $_ is the current list member
      #
      $out.="<tr>".(map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>" } @list)."</tr>";
    } elsif ($type eq "COL") { 
      #
      # ditto for a single column
      #
      $out.=join("",map {defined($_) ? "<tr><td>$_</td></tr>" : "<tr><td>(null)</td></tr>"} @list);
    } else { 
      #
      # For a 2D table, it's a bit more complicated...
      #
      $out.= join("",map {"<tr>$_</tr>"} (map {join("",map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>"} @{$_})} @list));
    }
    $out.="</table>";
  } else {
    # if no header row or list, then just say none.
    $out.="(none)";
  }
  return $out;
}


#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
sub MakeTableColor {
    my ( $id, $type, $headerlistref, $color, @list ) = @_;
    my $out;

    # check color
    my $fcolor = "black";
    if ( ( $color eq "blue" ) || ( $color eq "red" ) ) {
        $fcolor = "white";
    }

    #
    # Check to see if there is anything to output
    #
    if ( ( defined $headerlistref ) || ( $#list >= 0 ) ) {

        # if there is, begin a table
        #
        $out
            = "<table id=\"$id\" border=\"1\" bgcolor=\"$color\" style=\"color:$fcolor\">";
        #
        # if there is a header list, then output it in bold
        #
        if ( defined $headerlistref ) {
            $out
                .= "<tr>"
                . join( "", ( map {"<td><b>$_</b></td>"} @{$headerlistref} ) )
                . "</tr>";
        }
        #
        # If it's a single row, just output it in an obvious way
        #
        if ( $type eq "ROW" ) {
         #
         # map {code} @list means "apply this code to every member of the list
         # and return the modified list.  $_ is the current list member
         #
            $out
                .= "<tr>"
                . ( map { defined($_) ? "<td>$_</td>" : "<td>(null)</td>" }
                    @list )
                . "</tr>";
        }
        elsif ( $type eq "COL" ) {
            #
            # ditto for a single column
            #
            $out .= join(
                "",
                map {
                    defined($_)
                        ? "<tr><td>$_</td></tr>"
                        : "<tr><td>(null)</td></tr>"
                } @list
            );
        }
        else {
            #
            # For a 2D table, it's a bit more complicated...
            #
            $out .= join(
                "",
                map {"<tr>$_</tr>"} (
                    map {
                        join(
                            "",
                            map {
                                defined($_)
                                    ? "<td>$_</td>"
                                    : "<td>(null)</td>"
                            } @{$_}
                            )
                    } @list
                )
            );
        }
        $out .= "</table>";
    }
    else {
        # if no header row or list, then just say none.
        $out .= "(none)";
    }
    return $out;
}

#
# Given a list of scalars, or a list of references to lists, generates
# an HTML <pre> section, one line per row, columns are tab-deliminted
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
#
# $html = MakeRaw($id, $type, @list);
#
sub MakeRaw {
  my ($id, $type,@list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  $out="<pre id=\"$id\">\n";
  #
  # If it's a single row, just output it in an obvious way
  #
  if ($type eq "ROW") { 
    #
    # map {code} @list means "apply this code to every member of the list
    # and return the modified list.  $_ is the current list member
    #
    $out.=join("\t",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } elsif ($type eq "COL") { 
    #
    # ditto for a single column
    #
    $out.=join("\n",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } else {
    #
    # For a 2D table
    #
    foreach my $r (@list) { 
      $out.= join("\t", map { defined($_) ? $_ : "(null)" } @{$r});
      $out.="\n";
    }
  }
  $out.="</pre>\n";
  return $out;
}


 sub AddInviteCode {
   my ($userInvited, $code)=@_;
   eval {ExecSQL($dbuser, $password,"insert into user_code (code, username) values (?,?)",undef, $code, $userInvited);};
  return $@;
 }

 sub RmLink {
  eval { ExecSQL($dbuser,$dbpasswd,"delete from user_code where code=?",undef,@_);};
  return $@;
}

sub CheckCode {
  my ($code) = @_;
    my @col;
    eval {
        @col = ExecSQL(
            $dbuser,
            $dbpasswd,
            "select count(*) from user_code where code=?",
            "COL",
            $code
        );
    };
    if ($@) {
        return 0;
    }
    else {
        return 1;
    }
}

sub AddOpinion2DB {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "insert into rwb_opinions (submitter,color,latitude,longitude) values (?,?,?,?)",
            undef,
            @_
        );
    };
    return $@;
}


#
# @list=ExecSQL($user, $password, $querystring, $type, @fill);
#
# Executes a SQL statement.  If $type is "ROW", returns first row in list
# if $type is "COL" returns first column.  Otherwise, returns
# the whole result table as a list of references to row lists.
# @fill are the fillers for positional parameters in $querystring
#
# ExecSQL executes "die" on failure.
#
sub ExecSQL {
  my ($user, $passwd, $querystring, $type, @fill) =@_;
  if ($debug) { 
    # if we are recording inputs, just push the query string and fill list onto the 
    # global sqlinput list
    push @sqlinput, "$querystring (".join(",",map {"'$_'"} @fill).")";
  }
  my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd);
  if (not $dbh) { 
    # if the connect failed, record the reason to the sqloutput list (if set)
    # and then die.
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't connect to the database because of ".$DBI::errstr."</b>";
    }
    die "Can't connect to database because of ".$DBI::errstr;
  }
  my $sth = $dbh->prepare($querystring);
  if (not $sth) { 
    #
    # If prepare failed, then record reason to sqloutput and then die
    #
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't prepare '$querystring' because of ".$DBI::errstr."</b>";
    }
    my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
    $dbh->disconnect();
    die $errstr;
  }
  if (not $sth->execute(@fill)) { 
    #
    # if exec failed, record to sqlout and die.
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't execute '$querystring' with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr."</b>";
    }
    my $errstr="Can't execute $querystring with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr;
    $dbh->disconnect();
    die $errstr;
  }
  #
  # The rest assumes that the data will be forthcoming.
  #
  #
  my @data;
  if (defined $type and $type eq "ROW") { 
    @data=$sth->fetchrow_array();
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","ROW",undef,@data);}
    $dbh->disconnect();
    return @data;
  }
  my @ret;
  while (@data=$sth->fetchrow_array()) {
    push @ret, [@data];
  }
  if (defined $type and $type eq "COL") { 
    @data = map {$_->[0]} @ret;
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","COL",undef,@data);}
    $dbh->disconnect();
    return @data;
  }
  $sth->finish();
  if ($debug) {push @sqloutput, MakeTable("debug_sql_output","2D",undef,@ret);}
  $dbh->disconnect();
  return @ret;
}


######################################################################
#
# Nothing important after this
#
######################################################################

# The following is necessary so that DBD::Oracle can
# find its butt
#
BEGIN {
  unless ($ENV{BEGIN_BLOCK}) {
    use Cwd;
    $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
    $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
    $ENV{ORACLE_SID}="CS339";
    $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',cwd().'/'.$0,@ARGV;
  }
}

