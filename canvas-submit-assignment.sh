# Get token
# Change it to wherever the token is
token=`cat ~/canvas_token`
if [[ $? -ne 0 ]]; then
	printf "No token file\n" >&2
	exit 1
fi

# Error output
errdir="/tmp/.com.remisiki.canvas"
mkdir -p $errdir
errfile="$errdir/assignmentSubmit.err"
rm -f $errfile
isDigit='^[0-9]+$'

# Get self id
selfId=`
	curl\
		-s\
		-X GET "https://umich.instructure.com/api/v1/users/self"\
		-H "authorization: Bearer $token"\
	| jq '.id'\
	2>$errfile
`
if [[ -s $errfile || $selfId == "null" ]]; then
	printf "User authentication failed\n" >&2
	exit 1
fi

# Fetch courses
# Filter out those useless
printf "Fetching courses..."
courses=`
	curl\
		-s\
		-X GET "https://umich.instructure.com/api/v1/users/self/favorites/courses"\
		-H "authorization: Bearer $token"\
	| jq '[.[] | select(.id == 562557 or .id == 529196 or .id == 137833 or .id == 564786 or .id == 137916 | not)]'\
	2>$errfile
`
printf "\r"
if [[ -s $errfile || $courses == "null" ]]; then
	printf "Fetching courses...Failed\n" >&2
	exit 1
fi
printf "Fetching courses...Done\n"
courseCount=`echo $courses | jq '. | length'`
output=""
for (( i = 0; i < courseCount; i++ )); do
	courseId=`echo $courses | jq '.['$i'].id'`
	output+=`printf "%d\t" $i`
	output+=`echo $courses | jq -r '.['$i'] | "\(.name)"'`
	output+=$'\n'
done
printf "%s" "$output"

# Read course selection
read -p "Select a course [0]: " courseIndex
if [[ -z $courseIndex ]]; then
	courseIndex=0
elif [[ (! $courseIndex =~ $isDigit) || ($courseIndex -ge $courseCount) ]]; then
	printf "Bad selection\n" >&2
	exit 1
fi
courseId=`echo $courses | jq '.['$courseIndex'].id'`

# Fetch asssigments due after currentTime
currentTime=`date "+%Y-%m-%dT%H:%M:%SZ" -u`
printf "Fetching assignments..."
assignments=`
	curl\
		-s\
		-X GET "https://umich.instructure.com/api/v1/courses/$courseId/assignments?per_page=50"\
		-H "authorization: Bearer $token"\
	| jq "[.[] | select(.due_at > \"$currentTime\")] | sort_by(.due_at)"\
	2>$errfile
`
printf "\r"
if [[ -s $errfile || $assignments == "null" ]]; then
	printf "Fetching assignments...Failed\n" >&2
	exit 1
fi
printf "Fetching assignments...Done\n"
output=""
assignmentCount=`echo $assignments | jq ". | length"`
for (( i = 0; i < assignmentCount; i++ )); do
	output+=`printf "%d\t" $i`
	output+=`echo $assignments | jq -r '.['$i'] | "Due time: \(.due_at), Name: \(.name)"'`
	output+=$'\n'
done
printf "%s" "$output"

# Read assignment selection
read -p "Select an assignment [0]: " assignmentIndex
if [[ -z $assignmentIndex ]]; then
	assignmentIndex=0
elif [[ (! $assignmentIndex =~ $isDigit) || ($assignmentIndex -ge $assignmentCount) ]]; then
	printf "Bad selection\n" >&2
	exit 1
fi
assignmentId=`echo $assignments | jq '.['$assignmentIndex'].id'`

# Fetch upload url
printf "Fetching upload url..."
firstFileName=`basename $1`
uploadUrl=`
	curl\
		-s\
		-X POST "https://umich.instructure.com/api/v1/courses/$courseId/assignments/$assignmentId/submissions/$selfId/files"\
		-H "authorization: Bearer $token"\
		-H "content-type: application/json;charset=UTF-8"\
		-d '{"name":"'$firstFileName'","content_type":"unknown/unknown","submit_assignment":true,"no_redirect":true}'\
	| jq -r '.upload_url'\
	2>$errfile
`
printf "\r"
if [[ -s $errfile || $uploadUrl == "null" ]]; then
	printf "Fetching upload url...Failed\n" >&2
	exit 1
fi
printf "Fetching upload url...Done\n"

# Upload files
files=$@
fileCount=$#
fileIds=()
for (( i = 1; i <= fileCount; i++ )); do
	file=${!i}
	printf "Uploading $file ($i/$fileCount)..."
	fileId=`
		curl\
			-s\
			-X POST $uploadUrl\
			-F "file=@$file"\
		| jq '.id'\
		2>$errfile
	`
	printf "\r"
	if [[ -s $errfile || $fileId == "null" ]]; then
		printf "Uploading $file ($i/$fileCount)...Failed\n" >&2
		exit 1
	fi
	fileIds+=($fileId)
	printf "Uploading $file ($i/$fileCount)...Done\n"
done
jointFileIds=`printf "\"%s\"," "${fileIds[@]}"`
jointFileIds="${jointFileIds%,}"

# Submit
# I have no idea where submissionID comes from, here takes base64 of 'Submission-92000000' and it works for all my submission.
printf "Submitting..."
submitError=`
	curl\
		-s\
		-X POST "https://umich.instructure.com/api/graphql"\
		-H "authorization: Bearer $token"\
		-H "Content-Type:application/json"\
		-d '{"operationName":"CreateSubmission","variables":{"assignmentLid":"'$assignmentId'","submissionID":"U3VibWlzc2lvbi05MjAwMDAwMA==","fileIds":['$jointFileIds'],"type":"online_upload"},"query":"mutation CreateSubmission($assignmentLid: ID!, $submissionID: ID!, $type: OnlineSubmissionType!, $body: String, $fileIds: [ID!], $mediaId: ID, $resourceLinkLookupUuid: String, $url: String) {\n  createSubmission(input: {assignmentId: $assignmentLid, submissionType: $type, body: $body, fileIds: $fileIds, mediaId: $mediaId, resourceLinkLookupUuid: $resourceLinkLookupUuid, url: $url}) {\n    submission {\n      ...Submission\n      __typename\n  }\n    errors {\n      ...Error\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment Error on ValidationError {\n  attribute\n  message\n  __typename\n}\n\nfragment Submission on Submission {\n  ...SubmissionInterface\n  _id\n  id\n  __typename\n}\n\nfragment SubmissionInterface on SubmissionInterface {\n  attachment {\n    ...SubmissionFile\n    __typename\n  }\n  attachments {\n    ...SubmissionFile\n    __typename\n  }\n  attempt\n  body\n  deductedPoints\n  enteredGrade\n  extraAttempts\n  grade\n  gradeHidden\n  gradingStatus\n  latePolicyStatus\n  mediaObject {\n    ...MediaObject\n    __typename\n  }\n  originalityData\n  resourceLinkLookupUuid\n  state\n  submissionDraft {\n    ...SubmissionDraft\n    __typename\n  }\n  submissionStatus\n  submissionType\n  submittedAt\n  turnitinData {\n    ...TurnitinData\n    __typename\n  }\n  feedbackForCurrentAttempt\n  unreadCommentCount\n  url\n  assignedAssessments {\n    ...AssessmentRequest\n    __typename\n  }\n  __typename\n}\n\nfragment MediaObject on MediaObject {\n  id\n  _id\n  mediaSources {\n    ...MediaSource\n    __typename\n  }\n  mediaTracks {\n    ...MediaTrack\n    __typename\n  }\n  mediaType\n  title\n  __typename\n}\n\nfragment MediaSource on MediaSource {\n  height\n  src: url\n  type: contentType\n  width\n  __typename\n}\n\nfragment MediaTrack on MediaTrack {\n  _id\n  locale\n  content\n  kind\n  __typename\n}\n\nfragment SubmissionFile on File {\n  _id\n  displayName\n  id\n  mimeClass\n  submissionPreviewUrl(submissionId: $submissionID)\n  size\n  thumbnailUrl\n  url\n  __typename\n}\n\nfragment SubmissionDraft on SubmissionDraft {\n  _id\n  activeSubmissionType\n  attachments {\n    ...SubmissionDraftFile\n    __typename\n  }\n  body(rewriteUrls: false)\n  externalTool {\n    ...ExternalTool\n    __typename\n  }\n  ltiLaunchUrl\n  mediaObject {\n    ...MediaObject\n    __typename\n  }\n  meetsMediaRecordingCriteria\n  meetsAssignmentCriteria\n  meetsBasicLtiLaunchCriteria\n  meetsTextEntryCriteria\n  meetsUploadCriteria\n  meetsUrlCriteria\n  meetsStudentAnnotationCriteria\n  resourceLinkLookupUuid\n  url\n  __typename\n}\n\nfragment ExternalTool on ExternalTool {\n  _id\n  description\n  name\n  settings {\n    iconUrl\n    __typename\n  }\n  __typename\n}\n\nfragment SubmissionDraftFile on File {\n  _id\n  displayName\n  mimeClass\n  thumbnailUrl\n  __typename\n}\n\nfragment AssessmentRequest on AssessmentRequest {\n  anonymizedUser {\n    _id\n    displayName: shortName\n    __typename\n  }\n  anonymousId\n  workflowState\n  __typename\n}\n\nfragment TurnitinData on TurnitinData {\n  reportUrl\n  score\n  status\n  state\n  __typename\n}\n"}'\
	| jq '.errors'\
	2>$errfile
`
printf "\r"
if [[ -s $errfile || $submitError != "null" ]]; then
	printf "Submitting...Failed\n$submitError" >&2
	exit 1
else
	printf "Submitting...Done\n"
fi
